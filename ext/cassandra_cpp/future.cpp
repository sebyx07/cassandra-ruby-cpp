#include "cassandra_cpp.h"

// Memory management functions
static void future_mark(void* ptr) {
    future_wrapper_t* wrapper = (future_wrapper_t*)ptr;
    if (wrapper) {
        rb_gc_mark(wrapper->callback_proc);
        rb_gc_mark(wrapper->error_callback_proc);
        rb_gc_mark(wrapper->session_ref);
    }
}

static void future_free(void* ptr) {
    future_wrapper_t* wrapper = (future_wrapper_t*)ptr;
    if (wrapper) {
        if (wrapper->future) {
            cass_future_free(wrapper->future);
        }
        xfree(wrapper);
    }
}

const rb_data_type_t future_type = {
    "CassandraCpp::NativeFuture",
    { future_mark, future_free, 0 },
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};


// Create a new Future object
static VALUE future_new(VALUE klass, CassFuture* cass_future, VALUE session_ref, future_type_t type) {
    future_wrapper_t* wrapper = ALLOC(future_wrapper_t);
    wrapper->future = cass_future;
    wrapper->callback_proc = Qnil;
    wrapper->error_callback_proc = Qnil;
    wrapper->session_ref = session_ref;
    wrapper->type = type;
    
    VALUE future_obj = TypedData_Wrap_Struct(klass, &future_type, wrapper);
    return future_obj;
}

// Ruby method: future.then(&block)
static VALUE future_then(VALUE self) {
    if (!rb_block_given_p()) {
        rb_raise(rb_eArgError, "no block given for then");
    }
    
    future_wrapper_t* wrapper;
    TypedData_Get_Struct(self, future_wrapper_t, &future_type, wrapper);
    
    wrapper->callback_proc = rb_block_proc();
    return self;
}

// Ruby method: future.rescue(&block)
static VALUE future_rescue(VALUE self) {
    if (!rb_block_given_p()) {
        rb_raise(rb_eArgError, "no block given for rescue");
    }
    
    future_wrapper_t* wrapper;
    TypedData_Get_Struct(self, future_wrapper_t, &future_type, wrapper);
    
    wrapper->error_callback_proc = rb_block_proc();
    return self;
}

// Ruby method: future.value(timeout = nil)
static VALUE future_value(int argc, VALUE* argv, VALUE self) {
    VALUE timeout_val;
    rb_scan_args(argc, argv, "01", &timeout_val);
    
    future_wrapper_t* wrapper;
    TypedData_Get_Struct(self, future_wrapper_t, &future_type, wrapper);
    
    // Wait for the future with optional timeout
    cass_bool_t result;
    if (NIL_P(timeout_val)) {
        cass_future_wait(wrapper->future);
        result = cass_true;
    } else {
        double timeout_seconds = NUM2DBL(timeout_val);
        cass_uint64_t timeout_us = (cass_uint64_t)(timeout_seconds * 1000000);
        result = cass_future_wait_timed(wrapper->future, timeout_us);
    }
    
    if (!result) {
        rb_raise(rb_eCassandraError, "Future timed out");
    }
    
    // Check for errors
    CassError rc = cass_future_error_code(wrapper->future);
    if (rc != CASS_OK) {
        raise_cassandra_error(wrapper->future, "future execution");
    }
    
    // Handle different future types
    if (wrapper->type == FUTURE_TYPE_PREPARE) {
        // For prepare operations, get the prepared statement
        const CassPrepared* prepared = cass_future_get_prepared(wrapper->future);
        
        // Create prepared statement wrapper
        prepared_statement_wrapper_t* prepared_wrapper = ALLOC(prepared_statement_wrapper_t);
        prepared_wrapper->prepared = prepared;
        prepared_wrapper->session_ref = wrapper->session_ref;
        
        VALUE prepared_obj = TypedData_Wrap_Struct(rb_cPreparedStatement, &prepared_statement_type, prepared_wrapper);
        
        // Keep reference to prevent session from being GC'd
        rb_iv_set(prepared_obj, "@session", wrapper->session_ref);
        
        return prepared_obj;
    } else {
        // For execute operations, get the result and convert to Ruby
        const CassResult* cass_result = cass_future_get_result(wrapper->future);
        VALUE rows = rb_ary_new();
        
        if (cass_result) {
            CassIterator* iterator = cass_iterator_from_result(cass_result);
            
            while (cass_iterator_next(iterator)) {
                const CassRow* row = cass_iterator_get_row(iterator);
                size_t column_count = cass_result_column_count(cass_result);
                
                VALUE row_hash = rb_hash_new();
                
                for (size_t i = 0; i < column_count; i++) {
                    const char* column_name;
                    size_t column_name_length;
                    cass_result_column_name(cass_result, i, &column_name, &column_name_length);
                    
                    const CassValue* value = cass_row_get_column(row, i);
                    VALUE ruby_value = convert_cass_value_to_ruby(value);
                    
                    VALUE column_key = rb_str_new(column_name, column_name_length);
                    rb_hash_aset(row_hash, column_key, ruby_value);
                }
                
                rb_ary_push(rows, row_hash);
            }
            
            cass_iterator_free(iterator);
            cass_result_free(cass_result);
        }
        
        return rows;
    }
}

// Ruby method: future.ready?
static VALUE future_ready_p(VALUE self) {
    future_wrapper_t* wrapper;
    TypedData_Get_Struct(self, future_wrapper_t, &future_type, wrapper);
    
    return cass_future_ready(wrapper->future) ? Qtrue : Qfalse;
}

// Ruby method: future.execute_callbacks
static VALUE future_execute_callbacks(VALUE self) {
    future_wrapper_t* wrapper;
    TypedData_Get_Struct(self, future_wrapper_t, &future_type, wrapper);
    
    // For now, just check if future is ready and execute callbacks immediately
    // This is a simplified implementation - a production version would use
    // a better async mechanism
    if (cass_future_ready(wrapper->future)) {
        CassError rc = cass_future_error_code(wrapper->future);
        
        if (rc == CASS_OK && !NIL_P(wrapper->callback_proc)) {
            // Success - call success callback
            VALUE result;
            
            if (wrapper->type == FUTURE_TYPE_PREPARE) {
                const CassPrepared* prepared = cass_future_get_prepared(wrapper->future);
                prepared_statement_wrapper_t* prepared_wrapper = ALLOC(prepared_statement_wrapper_t);
                prepared_wrapper->prepared = prepared;
                prepared_wrapper->session_ref = wrapper->session_ref;
                
                VALUE prepared_obj = TypedData_Wrap_Struct(rb_cPreparedStatement, &prepared_statement_type, prepared_wrapper);
                rb_iv_set(prepared_obj, "@session", wrapper->session_ref);
                result = prepared_obj;
            } else {
                const CassResult* cass_result = cass_future_get_result(wrapper->future);
                VALUE rows = rb_ary_new();
                
                if (cass_result) {
                    CassIterator* iterator = cass_iterator_from_result(cass_result);
                    
                    while (cass_iterator_next(iterator)) {
                        const CassRow* row = cass_iterator_get_row(iterator);
                        size_t column_count = cass_result_column_count(cass_result);
                        
                        VALUE row_hash = rb_hash_new();
                        
                        for (size_t i = 0; i < column_count; i++) {
                            const char* column_name;
                            size_t column_name_length;
                            cass_result_column_name(cass_result, i, &column_name, &column_name_length);
                            
                            const CassValue* value = cass_row_get_column(row, i);
                            VALUE ruby_value = convert_cass_value_to_ruby(value);
                            
                            VALUE column_key = rb_str_new(column_name, column_name_length);
                            rb_hash_aset(row_hash, column_key, ruby_value);
                        }
                        
                        rb_ary_push(rows, row_hash);
                    }
                    
                    cass_iterator_free(iterator);
                    cass_result_free(cass_result);
                }
                
                result = rows;
            }
            
            rb_funcall(wrapper->callback_proc, rb_intern("call"), 1, result);
            
        } else if (rc != CASS_OK && !NIL_P(wrapper->error_callback_proc)) {
            // Error - call error callback
            const char* message;
            size_t message_length;
            cass_future_error_message(wrapper->future, &message, &message_length);
            
            VALUE error_msg = rb_str_new(message, message_length);
            rb_funcall(wrapper->error_callback_proc, rb_intern("call"), 1, error_msg);
        }
    }
    
    return self;
}

// C function to create Future from CassFuture (called from session.cpp)
VALUE create_future_from_cass_future(CassFuture* cass_future, VALUE session_ref, future_type_t type) {
    return future_new(rb_cFuture, cass_future, session_ref, type);
}

void init_future() {
    rb_cFuture = rb_define_class_under(rb_cCassandraCpp, "NativeFuture", rb_cObject);
    rb_undef_alloc_func(rb_cFuture);
    
    rb_define_method(rb_cFuture, "then", (VALUE(*)(...))future_then, 0);
    rb_define_method(rb_cFuture, "rescue", (VALUE(*)(...))future_rescue, 0);
    rb_define_method(rb_cFuture, "value", (VALUE(*)(...))future_value, -1);
    rb_define_method(rb_cFuture, "ready?", (VALUE(*)(...))future_ready_p, 0);
    rb_define_method(rb_cFuture, "execute_callbacks", (VALUE(*)(...))future_execute_callbacks, 0);
}
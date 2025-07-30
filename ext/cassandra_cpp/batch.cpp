#include "cassandra_cpp.h"

// Memory management functions
static void batch_free(void* ptr) {
    batch_wrapper_t* wrapper = (batch_wrapper_t*)ptr;
    if (wrapper) {
        if (wrapper->batch) {
            cass_batch_free(wrapper->batch);
        }
        xfree(wrapper);
    }
}

const rb_data_type_t batch_type = {
    "CassandraCpp::NativeBatch",
    { 0, batch_free, 0 },
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

// Batch methods
static VALUE batch_add_statement(VALUE self, VALUE statement_or_query, VALUE params) {
    batch_wrapper_t* batch_wrapper;
    TypedData_Get_Struct(self, batch_wrapper_t, &batch_type, batch_wrapper);
    
    CassError rc = CASS_OK;
    
    if (TYPE(statement_or_query) == T_STRING) {
        // Simple query string
        const char* query = StringValueCStr(statement_or_query);
        
        // Count parameters in the query to create statement with right parameter count
        size_t param_count = 0;
        if (!NIL_P(params) && TYPE(params) == T_ARRAY) {
            param_count = RARRAY_LEN(params);
        }
        
        CassStatement* statement = cass_statement_new(query, param_count);
        
        // Bind parameters if provided
        if (param_count > 0) {
            for (size_t i = 0; i < param_count; i++) {
                VALUE param = rb_ary_entry(params, i);
                rc = bind_ruby_value_to_statement(statement, i, param);
                if (rc != CASS_OK) {
                    cass_statement_free(statement);
                    rb_raise(rb_eCassandraError, "Failed to bind parameter at index %zu: %s", i, cass_error_desc(rc));
                }
            }
        }
        
        rc = cass_batch_add_statement(batch_wrapper->batch, statement);
        cass_statement_free(statement); // Batch takes ownership, safe to free
    } else {
        // Assume it's a NativeStatement object
        statement_wrapper_t* statement_wrapper;
        TypedData_Get_Struct(statement_or_query, statement_wrapper_t, &statement_type, statement_wrapper);
        
        rc = cass_batch_add_statement(batch_wrapper->batch, statement_wrapper->statement);
    }
    
    if (rc != CASS_OK) {
        rb_raise(rb_eCassandraError, "Failed to add statement to batch: %s", cass_error_desc(rc));
    }
    
    return self;
}

static VALUE batch_execute(VALUE self) {
    batch_wrapper_t* batch_wrapper;
    TypedData_Get_Struct(self, batch_wrapper_t, &batch_type, batch_wrapper);
    
    // Get session from batch
    VALUE session = rb_iv_get(self, "@session");
    session_wrapper_t* session_wrapper;
    TypedData_Get_Struct(session, session_wrapper_t, &session_type, session_wrapper);
    
    // Execute batch
    CassFuture* future = cass_session_execute_batch(session_wrapper->session, batch_wrapper->batch);
    
    // Wait for result
    CassError rc = cass_future_error_code(future);
    if (rc != CASS_OK) {
        raise_cassandra_error(future, "batch execution");
    }
    
    // Get result (batch operations typically don't return data, but we'll handle it)
    const CassResult* result = cass_future_get_result(future);
    VALUE rows = rb_ary_new(); // Empty array for batch results
    
    if (result) {
        // Convert result to Ruby array (reuse from session.cpp)
        CassIterator* iterator = cass_iterator_from_result(result);
        
        while (cass_iterator_next(iterator)) {
            const CassRow* row = cass_iterator_get_row(iterator);
            size_t column_count = cass_result_column_count(result);
            
            VALUE row_hash = rb_hash_new();
            
            for (size_t i = 0; i < column_count; i++) {
                const char* column_name;
                size_t column_name_length;
                cass_result_column_name(result, i, &column_name, &column_name_length);
                
                const CassValue* value = cass_row_get_column(row, i);
                VALUE ruby_value = convert_cass_value_to_ruby(value);
                
                VALUE column_key = rb_str_new(column_name, column_name_length);
                rb_hash_aset(row_hash, column_key, ruby_value);
            }
            
            rb_ary_push(rows, row_hash);
        }
        
        cass_iterator_free(iterator);
        cass_result_free(result);
    }
    
    // Cleanup
    cass_future_free(future);
    
    return rows;
}

static VALUE batch_set_consistency(VALUE self, VALUE consistency) {
    batch_wrapper_t* batch_wrapper;
    TypedData_Get_Struct(self, batch_wrapper_t, &batch_type, batch_wrapper);
    
    CassConsistency cass_consistency = (CassConsistency)NUM2INT(consistency);
    CassError rc = cass_batch_set_consistency(batch_wrapper->batch, cass_consistency);
    
    if (rc != CASS_OK) {
        rb_raise(rb_eCassandraError, "Failed to set batch consistency: %s", cass_error_desc(rc));
    }
    
    return self;
}

void init_batch() {
    rb_cBatch = rb_define_class_under(rb_cCassandraCpp, "NativeBatch", rb_cObject);
    rb_undef_alloc_func(rb_cBatch);
    rb_define_method(rb_cBatch, "add_statement", (VALUE(*)(...))batch_add_statement, 2);
    rb_define_method(rb_cBatch, "execute", (VALUE(*)(...))batch_execute, 0);
    rb_define_method(rb_cBatch, "consistency=", (VALUE(*)(...))batch_set_consistency, 1);
}
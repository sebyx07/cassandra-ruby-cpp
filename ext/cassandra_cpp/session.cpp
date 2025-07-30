#include "cassandra_cpp.h"

// Memory management functions
static void session_free(void* ptr) {
    session_wrapper_t* wrapper = (session_wrapper_t*)ptr;
    if (wrapper) {
        // Session is owned by cluster, don't free here
        xfree(wrapper);
    }
}

const rb_data_type_t session_type = {
    "CassandraCpp::NativeSession",
    { 0, session_free, 0 },
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

// Convert CassResult to Ruby array
static VALUE convert_result_to_ruby(const CassResult* result) {
    VALUE rows = rb_ary_new();
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
    return rows;
}

// Session methods
static VALUE session_execute(VALUE self, VALUE query_str) {
    session_wrapper_t* wrapper;
    TypedData_Get_Struct(self, session_wrapper_t, &session_type, wrapper);
    
    const char* query = StringValueCStr(query_str);
    
    // Create statement
    CassStatement* statement = cass_statement_new(query, 0);
    
    // Execute query
    CassFuture* future = cass_session_execute(wrapper->session, statement);
    
    // Wait for result
    CassError rc = cass_future_error_code(future);
    if (rc != CASS_OK) {
        cass_statement_free(statement);
        raise_cassandra_error(future, "query execution");
    }
    
    // Get result
    const CassResult* result = cass_future_get_result(future);
    VALUE rows = convert_result_to_ruby(result);
    
    // Cleanup
    cass_result_free(result);
    cass_future_free(future);
    cass_statement_free(statement);
    
    return rows;
}

static VALUE session_close(VALUE self) {
    session_wrapper_t* wrapper;
    TypedData_Get_Struct(self, session_wrapper_t, &session_type, wrapper);
    
    if (wrapper->session) {
        CassFuture* close_future = cass_session_close(wrapper->session);
        cass_future_wait(close_future);
        cass_future_free(close_future);
        wrapper->session = NULL;
    }
    
    return Qnil;
}

static VALUE session_prepare(VALUE self, VALUE query_str) {
    session_wrapper_t* session_wrapper;
    TypedData_Get_Struct(self, session_wrapper_t, &session_type, session_wrapper);
    
    const char* query = StringValueCStr(query_str);
    
    // Prepare the statement
    CassFuture* prepare_future = cass_session_prepare(session_wrapper->session, query);
    
    // Wait for preparation
    CassError rc = cass_future_error_code(prepare_future);
    if (rc != CASS_OK) {
        raise_cassandra_error(prepare_future, "statement preparation");
    }
    
    // Get prepared statement
    const CassPrepared* prepared = cass_future_get_prepared(prepare_future);
    cass_future_free(prepare_future);
    
    // Create prepared statement wrapper
    prepared_statement_wrapper_t* prepared_wrapper = ALLOC(prepared_statement_wrapper_t);
    prepared_wrapper->prepared = prepared;
    prepared_wrapper->session_ref = self;
    
    VALUE prepared_obj = TypedData_Wrap_Struct(rb_cPreparedStatement, &prepared_statement_type, prepared_wrapper);
    
    // Keep reference to prevent session from being GC'd
    rb_iv_set(prepared_obj, "@session", self);
    rb_iv_set(prepared_obj, "@query", query_str);
    
    return prepared_obj;
}

static VALUE session_batch(int argc, VALUE* argv, VALUE self) {
    VALUE batch_type_val;
    rb_scan_args(argc, argv, "01", &batch_type_val);
    
    // Default to logged batch
    CassBatchType cass_batch_type = CASS_BATCH_TYPE_LOGGED;
    if (!NIL_P(batch_type_val)) {
        cass_batch_type = (CassBatchType)NUM2INT(batch_type_val);
    }
    
    // Create batch
    CassBatch* batch = cass_batch_new(cass_batch_type);
    
    // Create batch wrapper
    batch_wrapper_t* batch_wrapper = ALLOC(batch_wrapper_t);
    batch_wrapper->batch = batch;
    batch_wrapper->session_ref = self;
    
    VALUE batch_obj = TypedData_Wrap_Struct(rb_cBatch, &batch_type, batch_wrapper);
    
    // Keep reference to prevent session from being GC'd
    rb_iv_set(batch_obj, "@session", self);
    
    return batch_obj;
}

// Async execution method - returns a Future object
static VALUE session_execute_async(VALUE self, VALUE query_str) {
    session_wrapper_t* wrapper;
    TypedData_Get_Struct(self, session_wrapper_t, &session_type, wrapper);
    
    const char* query = StringValueCStr(query_str);
    
    // Create statement
    CassStatement* statement = cass_statement_new(query, 0);
    
    // Execute query asynchronously
    CassFuture* future = cass_session_execute(wrapper->session, statement);
    
    // Clean up statement (future holds reference to it)
    cass_statement_free(statement);
    
    // Create Ruby Future object
    VALUE future_obj = create_future_from_cass_future(future, self, FUTURE_TYPE_EXECUTE);
    
    return future_obj;
}

// Async prepare method - returns a Future object
static VALUE session_prepare_async(VALUE self, VALUE query_str) {
    session_wrapper_t* wrapper;
    TypedData_Get_Struct(self, session_wrapper_t, &session_type, wrapper);
    
    const char* query = StringValueCStr(query_str);
    
    // Prepare statement asynchronously
    CassFuture* future = cass_session_prepare(wrapper->session, query);
    
    // Create Ruby Future object
    VALUE future_obj = create_future_from_cass_future(future, self, FUTURE_TYPE_PREPARE);
    
    return future_obj;
}

void init_session() {
    rb_cSession = rb_define_class_under(rb_cCassandraCpp, "NativeSession", rb_cObject);
    rb_undef_alloc_func(rb_cSession);
    rb_define_method(rb_cSession, "execute", (VALUE(*)(...))session_execute, 1);
    rb_define_method(rb_cSession, "execute_async", (VALUE(*)(...))session_execute_async, 1);
    rb_define_method(rb_cSession, "close", (VALUE(*)(...))session_close, 0);
    rb_define_method(rb_cSession, "prepare", (VALUE(*)(...))session_prepare, 1);
    rb_define_method(rb_cSession, "prepare_async", (VALUE(*)(...))session_prepare_async, 1);
    rb_define_method(rb_cSession, "batch", (VALUE(*)(...))session_batch, -1);
}
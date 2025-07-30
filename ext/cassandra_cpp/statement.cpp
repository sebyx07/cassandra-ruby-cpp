#include "cassandra_cpp.h"

// Memory management functions
static void statement_free(void* ptr) {
    statement_wrapper_t* wrapper = (statement_wrapper_t*)ptr;
    if (wrapper) {
        if (wrapper->statement) {
            cass_statement_free(wrapper->statement);
        }
        xfree(wrapper);
    }
}

const rb_data_type_t statement_type = {
    "CassandraCpp::NativeStatement",
    { 0, statement_free, 0 },
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

// Helper to bind Ruby value to statement
static CassError bind_ruby_value_to_statement(CassStatement* statement, size_t index, VALUE value) {
    if (NIL_P(value)) {
        return cass_statement_bind_null(statement, index);
    }
    
    switch (TYPE(value)) {
        case T_STRING: {
            const char* str = StringValueCStr(value);
            
            // Check if this might be a UUID (36 chars with dashes)
            size_t len = RSTRING_LEN(value);
            if (len == 36 && str[8] == '-' && str[13] == '-' && str[18] == '-' && str[23] == '-') {
                CassUuid uuid;
                CassError rc = cass_uuid_from_string(str, &uuid);
                if (rc == CASS_OK) {
                    return cass_statement_bind_uuid(statement, index, uuid);
                }
            }
            
            // Otherwise bind as regular string
            return cass_statement_bind_string(statement, index, str);
        }
        case T_FIXNUM:
        case T_BIGNUM: {
            if (FIXNUM_P(value)) {
                cass_int32_t int_val = NUM2INT(value);
                return cass_statement_bind_int32(statement, index, int_val);
            } else {
                cass_int64_t bigint_val = NUM2LL(value);
                return cass_statement_bind_int64(statement, index, bigint_val);
            }
        }
        case T_TRUE:
        case T_FALSE: {
            cass_bool_t bool_val = RTEST(value) ? cass_true : cass_false;
            return cass_statement_bind_bool(statement, index, bool_val);
        }
        case T_FLOAT: {
            double double_val = NUM2DBL(value);
            return cass_statement_bind_double(statement, index, double_val);
        }
        default: {
            // Try to convert to string as fallback
            VALUE str_val = rb_obj_as_string(value);
            const char* str = StringValueCStr(str_val);
            return cass_statement_bind_string(statement, index, str);
        }
    }
}

// Statement methods
static VALUE statement_bind_by_index(int argc, VALUE* argv, VALUE self) {
    VALUE index, value;
    rb_scan_args(argc, argv, "2", &index, &value);
    
    statement_wrapper_t* wrapper;
    TypedData_Get_Struct(self, statement_wrapper_t, &statement_type, wrapper);
    
    size_t idx = NUM2SIZET(index);
    CassError rc = bind_ruby_value_to_statement(wrapper->statement, idx, value);
    
    if (rc != CASS_OK) {
        rb_raise(rb_eCassandraError, "Failed to bind parameter at index %zu: %s", idx, cass_error_desc(rc));
    }
    
    return self;
}

static VALUE statement_execute(VALUE self) {
    statement_wrapper_t* statement_wrapper;
    TypedData_Get_Struct(self, statement_wrapper_t, &statement_type, statement_wrapper);
    
    // Get session from prepared statement
    VALUE prepared_statement = rb_iv_get(self, "@prepared_statement");
    VALUE session = rb_iv_get(prepared_statement, "@session");
    
    session_wrapper_t* session_wrapper;
    TypedData_Get_Struct(session, session_wrapper_t, &session_type, session_wrapper);
    
    // Execute statement
    CassFuture* future = cass_session_execute(session_wrapper->session, statement_wrapper->statement);
    
    // Wait for result
    CassError rc = cass_future_error_code(future);
    if (rc != CASS_OK) {
        raise_cassandra_error(future, "prepared statement execution");
    }
    
    // Get result
    const CassResult* result = cass_future_get_result(future);
    
    // Convert result to Ruby array (reuse from session.cpp)
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
    
    // Cleanup
    cass_iterator_free(iterator);
    cass_result_free(result);
    cass_future_free(future);
    
    return rows;
}

void init_statement() {
    rb_cStatement = rb_define_class_under(rb_cCassandraCpp, "NativeStatement", rb_cObject);
    rb_undef_alloc_func(rb_cStatement);
    rb_define_method(rb_cStatement, "bind", (VALUE(*)(...))statement_bind_by_index, -1);
    rb_define_method(rb_cStatement, "execute", (VALUE(*)(...))statement_execute, 0);
}
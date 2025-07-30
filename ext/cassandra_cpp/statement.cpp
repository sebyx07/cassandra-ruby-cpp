#include "cassandra_cpp.h"
#include <limits.h>

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

// Helper to bind Ruby value to collection
CassError bind_ruby_value_to_collection(CassCollection* collection, VALUE value) {
    if (NIL_P(value)) {
        // Collections don't support null values in Cassandra
        // We'll skip null values instead
        return CASS_OK;
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
                    return cass_collection_append_uuid(collection, uuid);
                }
            }
            
            // Otherwise bind as regular string
            return cass_collection_append_string(collection, str);
        }
        case T_FIXNUM:
        case T_BIGNUM: {
            if (FIXNUM_P(value)) {
                cass_int32_t int_val = NUM2INT(value);
                return cass_collection_append_int32(collection, int_val);
            } else {
                cass_int64_t bigint_val = NUM2LL(value);
                return cass_collection_append_int64(collection, bigint_val);
            }
        }
        case T_TRUE:
        case T_FALSE: {
            cass_bool_t bool_val = RTEST(value) ? cass_true : cass_false;
            return cass_collection_append_bool(collection, bool_val);
        }
        case T_FLOAT: {
            double double_val = NUM2DBL(value);
            return cass_collection_append_double(collection, double_val);
        }
        case T_DATA:
        case T_OBJECT: {
            // Handle Time objects
            if (rb_obj_is_kind_of(value, rb_cTime)) {
                VALUE time_f = rb_funcall(value, rb_intern("to_f"), 0);
                double time_seconds = NUM2DBL(time_f);
                cass_int64_t timestamp_ms = (cass_int64_t)(time_seconds * 1000);
                return cass_collection_append_int64(collection, timestamp_ms);
            }
            
            // Fall through to string conversion
            VALUE str_val = rb_obj_as_string(value);
            const char* str = StringValueCStr(str_val);
            return cass_collection_append_string(collection, str);
        }
        default: {
            // Try to convert to string as fallback
            VALUE str_val = rb_obj_as_string(value);
            const char* str = StringValueCStr(str_val);
            return cass_collection_append_string(collection, str);
        }
    }
}

// Helper to bind Ruby value to statement (exposed for batch.cpp)
CassError bind_ruby_value_to_statement(CassStatement* statement, size_t index, VALUE value) {
    if (NIL_P(value)) {
        return cass_statement_bind_null(statement, index);
    }
    
    switch (TYPE(value)) {
        case T_STRING: {
            size_t len = RSTRING_LEN(value);
            const char* str = RSTRING_PTR(value);  // Use RSTRING_PTR instead of StringValueCStr to handle null bytes
            
            // Check if this might be a UUID (36 chars with dashes and no null bytes)
            if (len == 36 && str[8] == '-' && str[13] == '-' && str[18] == '-' && str[23] == '-') {
                // Only try UUID parsing if there are no null bytes
                bool has_null_bytes = false;
                for (size_t i = 0; i < len; i++) {
                    if (str[i] == '\0') {
                        has_null_bytes = true;
                        break;
                    }
                }
                
                if (!has_null_bytes) {
                    CassUuid uuid;
                    // Create null-terminated string for UUID parsing
                    char uuid_str[37];
                    memcpy(uuid_str, str, 36);
                    uuid_str[36] = '\0';
                    
                    CassError rc = cass_uuid_from_string(uuid_str, &uuid);
                    if (rc == CASS_OK) {
                        return cass_statement_bind_uuid(statement, index, uuid);
                    }
                }
            }
            
            // Check if this is binary data (contains null bytes or has ASCII-8BIT encoding)
            VALUE encoding = rb_funcall(value, rb_intern("encoding"), 0);
            VALUE encoding_name = rb_funcall(encoding, rb_intern("name"), 0);
            const char* enc_name = StringValueCStr(encoding_name);
            
            bool is_binary = (strcmp(enc_name, "ASCII-8BIT") == 0);
            
            // Also check for null bytes
            if (!is_binary) {
                for (size_t i = 0; i < len; i++) {
                    if (str[i] == '\0') {
                        is_binary = true;
                        break;
                    }
                }
            }
            
            if (is_binary) {
                // Treat as binary data (BLOB)
                return cass_statement_bind_bytes(statement, index, (const cass_byte_t*)str, len);
            } else {
                // Treat as regular string - safe to use StringValueCStr now
                const char* cstr = StringValueCStr(value);
                return cass_statement_bind_string(statement, index, cstr);
            }
        }
        case T_FIXNUM:
        case T_BIGNUM: {
            if (FIXNUM_P(value)) {
                long long_val = NUM2LONG(value);
                // Check if it fits in int32 range
                if (long_val >= INT32_MIN && long_val <= INT32_MAX) {
                    cass_int32_t int_val = (cass_int32_t)long_val;
                    return cass_statement_bind_int32(statement, index, int_val);
                } else {
                    // Use int64 for values outside int32 range
                    cass_int64_t bigint_val = (cass_int64_t)long_val;
                    return cass_statement_bind_int64(statement, index, bigint_val);
                }
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
        case T_ARRAY: {
            // Handle Ruby arrays as Cassandra LIST
            CassCollection* collection = cass_collection_new(CASS_COLLECTION_TYPE_LIST, RARRAY_LEN(value));
            
            for (long i = 0; i < RARRAY_LEN(value); i++) {
                VALUE item = rb_ary_entry(value, i);
                CassError rc = bind_ruby_value_to_collection(collection, item);
                if (rc != CASS_OK) {
                    cass_collection_free(collection);
                    return rc;
                }
            }
            
            CassError rc = cass_statement_bind_collection(statement, index, collection);
            cass_collection_free(collection);
            return rc;
        }
        case T_HASH: {
            // Handle Ruby hashes as Cassandra MAP
            VALUE keys = rb_funcall(value, rb_intern("keys"), 0);
            long map_size = RARRAY_LEN(keys);
            
            CassCollection* collection = cass_collection_new(CASS_COLLECTION_TYPE_MAP, map_size);
            
            for (long i = 0; i < map_size; i++) {
                VALUE key = rb_ary_entry(keys, i);
                VALUE val = rb_hash_aref(value, key);
                
                CassError rc = bind_ruby_value_to_collection(collection, key);
                if (rc != CASS_OK) {
                    cass_collection_free(collection);
                    return rc;
                }
                
                rc = bind_ruby_value_to_collection(collection, val);
                if (rc != CASS_OK) {
                    cass_collection_free(collection);
                    return rc;
                }
            }
            
            CassError rc = cass_statement_bind_collection(statement, index, collection);
            cass_collection_free(collection);
            return rc;
        }
        case T_DATA:
        case T_OBJECT: {
            // Check for specific Ruby types
            VALUE klass = rb_obj_class(value);
            
            // Check if it's a Time object
            if (rb_obj_is_kind_of(value, rb_cTime)) {
                // Convert Ruby Time to Cassandra timestamp (milliseconds since epoch)
                VALUE time_f = rb_funcall(value, rb_intern("to_f"), 0);
                double time_seconds = NUM2DBL(time_f);
                cass_int64_t timestamp_ms = (cass_int64_t)(time_seconds * 1000);
                return cass_statement_bind_int64(statement, index, timestamp_ms);
            }
            
            // Get class name for other types
            VALUE klass_name = rb_class_name(klass);
            const char* class_name = StringValueCStr(klass_name);
            
            if (strcmp(class_name, "BigDecimal") == 0) {
                // Convert BigDecimal to string for now (simplified implementation)
                VALUE decimal_str = rb_funcall(value, rb_intern("to_s"), 0);
                const char* str = StringValueCStr(decimal_str);
                return cass_statement_bind_string(statement, index, str);
            } else if (strcmp(class_name, "Set") == 0) {
                // Handle Ruby Set as Cassandra SET
                VALUE array = rb_funcall(value, rb_intern("to_a"), 0);
                long set_size = RARRAY_LEN(array);
                
                CassCollection* collection = cass_collection_new(CASS_COLLECTION_TYPE_SET, set_size);
                
                for (long i = 0; i < set_size; i++) {
                    VALUE item = rb_ary_entry(array, i);
                    CassError rc = bind_ruby_value_to_collection(collection, item);
                    if (rc != CASS_OK) {
                        cass_collection_free(collection);
                        return rc;
                    }
                }
                
                CassError rc = cass_statement_bind_collection(statement, index, collection);
                cass_collection_free(collection);
                return rc;
            }
            
            // Fall through to string conversion for other objects
            VALUE str_val = rb_obj_as_string(value);
            const char* str = StringValueCStr(str_val);
            return cass_statement_bind_string(statement, index, str);
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

static VALUE statement_execute_async(VALUE self) {
    statement_wrapper_t* statement_wrapper;
    TypedData_Get_Struct(self, statement_wrapper_t, &statement_type, statement_wrapper);
    
    // Get session from prepared statement
    VALUE prepared_statement = rb_iv_get(self, "@prepared_statement");
    VALUE session = rb_iv_get(prepared_statement, "@session");
    
    session_wrapper_t* session_wrapper;
    TypedData_Get_Struct(session, session_wrapper_t, &session_type, session_wrapper);
    
    // Execute statement asynchronously
    CassFuture* future = cass_session_execute(session_wrapper->session, statement_wrapper->statement);
    
    // Create Ruby Future object
    VALUE future_obj = create_future_from_cass_future(future, session, FUTURE_TYPE_EXECUTE);
    
    return future_obj;
}

void init_statement() {
    rb_cStatement = rb_define_class_under(rb_cCassandraCpp, "NativeStatement", rb_cObject);
    rb_undef_alloc_func(rb_cStatement);
    rb_define_method(rb_cStatement, "bind", (VALUE(*)(...))statement_bind_by_index, -1);
    rb_define_method(rb_cStatement, "execute", (VALUE(*)(...))statement_execute, 0);
    rb_define_method(rb_cStatement, "execute_async", (VALUE(*)(...))statement_execute_async, 0);
}
#include "cassandra_cpp.h"

// Global Ruby class references
VALUE rb_cCassandraCpp;
VALUE rb_cCluster;
VALUE rb_cSession;
VALUE rb_cPreparedStatement;
VALUE rb_cStatement;
VALUE rb_eCassandraError;

// Helper function to raise Cassandra errors
void raise_cassandra_error(CassFuture* future, const char* operation) {
    const char* message;
    size_t message_length;
    cass_future_error_message(future, &message, &message_length);
    
    VALUE error_msg = rb_sprintf("Cassandra %s error: %.*s", 
                                operation, (int)message_length, message);
    rb_raise(rb_eCassandraError, "%s", StringValueCStr(error_msg));
}

// Helper function to convert CassValue to Ruby value
VALUE convert_cass_value_to_ruby(const CassValue* value) {
    if (cass_value_is_null(value)) {
        return Qnil;
    }
    
    CassValueType value_type = cass_value_type(value);
    
    switch (value_type) {
        case CASS_VALUE_TYPE_TEXT:
        case CASS_VALUE_TYPE_VARCHAR: {
            const char* str;
            size_t str_length;
            cass_value_get_string(value, &str, &str_length);
            return rb_str_new(str, str_length);
        }
        case CASS_VALUE_TYPE_INT: {
            cass_int32_t int_val;
            cass_value_get_int32(value, &int_val);
            return INT2NUM(int_val);
        }
        case CASS_VALUE_TYPE_BIGINT: {
            cass_int64_t bigint_val;
            cass_value_get_int64(value, &bigint_val);
            return LL2NUM(bigint_val);
        }
        case CASS_VALUE_TYPE_BOOLEAN: {
            cass_bool_t bool_val;
            cass_value_get_bool(value, &bool_val);
            return bool_val ? Qtrue : Qfalse;
        }
        case CASS_VALUE_TYPE_UUID: {
            CassUuid uuid_val;
            cass_value_get_uuid(value, &uuid_val);
            char uuid_str[CASS_UUID_STRING_LENGTH];
            cass_uuid_string(uuid_val, uuid_str);
            return rb_str_new_cstr(uuid_str);
        }
        case CASS_VALUE_TYPE_FLOAT: {
            cass_float_t float_val;
            cass_value_get_float(value, &float_val);
            return DBL2NUM(float_val);
        }
        case CASS_VALUE_TYPE_DOUBLE: {
            cass_double_t double_val;
            cass_value_get_double(value, &double_val);
            return DBL2NUM(double_val);
        }
        default:
            return rb_str_new_cstr("[unsupported type]");
    }
}
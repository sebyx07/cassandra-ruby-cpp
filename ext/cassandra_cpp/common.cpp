#include "cassandra_cpp.h"
#include <math.h>

// Global Ruby class references
VALUE rb_cCassandraCpp;
VALUE rb_cCluster;
VALUE rb_cSession;
VALUE rb_cPreparedStatement;
VALUE rb_cStatement;
VALUE rb_cBatch;
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
        case CASS_VALUE_TYPE_TIMESTAMP: {
            cass_int64_t timestamp_val;
            cass_value_get_int64(value, &timestamp_val);
            // Convert milliseconds since epoch to Ruby Time
            double time_seconds = (double)timestamp_val / 1000.0;
            return rb_time_new(time_seconds, (time_seconds - floor(time_seconds)) * 1000000);
        }
        case CASS_VALUE_TYPE_DECIMAL: {
            const cass_byte_t* decimal_bytes;
            size_t decimal_size;
            cass_int32_t scale;
            cass_value_get_decimal(value, &decimal_bytes, &decimal_size, &scale);
            
            // Convert to BigDecimal string representation
            // This is a simplified implementation - for production use, 
            // you'd want proper arbitrary precision decimal handling
            VALUE decimal_str = rb_str_new_cstr("0");
            
            // Try to load BigDecimal if available
            VALUE big_decimal_class = rb_const_get_at(rb_cObject, rb_intern("BigDecimal"));
            if (!NIL_P(big_decimal_class)) {
                return rb_funcall(big_decimal_class, rb_intern("new"), 1, decimal_str);
            }
            
            return decimal_str;
        }
        case CASS_VALUE_TYPE_BLOB: {
            const cass_byte_t* blob_bytes;
            size_t blob_size;
            cass_value_get_bytes(value, &blob_bytes, &blob_size);
            return rb_str_new((const char*)blob_bytes, blob_size);
        }
        case CASS_VALUE_TYPE_LIST: {
            VALUE array = rb_ary_new();
            CassIterator* iterator = cass_iterator_from_collection(value);
            
            if (iterator != NULL) {
                while (cass_iterator_next(iterator)) {
                    const CassValue* item_value = cass_iterator_get_value(iterator);
                    VALUE ruby_item = convert_cass_value_to_ruby(item_value);
                    rb_ary_push(array, ruby_item);
                }
                cass_iterator_free(iterator);
            }
            
            return array;
        }
        case CASS_VALUE_TYPE_SET: {
            VALUE set_class = rb_const_get_at(rb_cObject, rb_intern("Set"));
            VALUE set = rb_funcall(set_class, rb_intern("new"), 0);
            CassIterator* iterator = cass_iterator_from_collection(value);
            
            if (iterator != NULL) {
                while (cass_iterator_next(iterator)) {
                    const CassValue* item_value = cass_iterator_get_value(iterator);
                    VALUE ruby_item = convert_cass_value_to_ruby(item_value);
                    rb_funcall(set, rb_intern("add"), 1, ruby_item);
                }
                cass_iterator_free(iterator);
            }
            
            return set;
        }
        case CASS_VALUE_TYPE_MAP: {
            VALUE hash = rb_hash_new();
            CassIterator* iterator = cass_iterator_from_map(value);
            
            if (iterator != NULL) {
                while (cass_iterator_next(iterator)) {
                    const CassValue* key_value = cass_iterator_get_map_key(iterator);
                    const CassValue* val_value = cass_iterator_get_map_value(iterator);
                    
                    VALUE ruby_key = convert_cass_value_to_ruby(key_value);
                    VALUE ruby_val = convert_cass_value_to_ruby(val_value);
                    
                    rb_hash_aset(hash, ruby_key, ruby_val);
                }
                cass_iterator_free(iterator);
            }
            
            return hash;
        }
        case CASS_VALUE_TYPE_TUPLE: {
            CassIterator* iterator = cass_iterator_from_tuple(value);
            VALUE array = rb_ary_new();
            
            while (cass_iterator_next(iterator)) {
                const CassValue* item_value = cass_iterator_get_value(iterator);
                VALUE ruby_item = convert_cass_value_to_ruby(item_value);
                rb_ary_push(array, ruby_item);
            }
            
            cass_iterator_free(iterator);
            return array;
        }
        default:
            return rb_str_new_cstr("[unsupported type]");
    }
}
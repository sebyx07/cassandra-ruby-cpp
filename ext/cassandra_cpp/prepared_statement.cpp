#include "cassandra_cpp.h"

// Memory management functions
static void prepared_statement_free(void* ptr) {
    prepared_statement_wrapper_t* wrapper = (prepared_statement_wrapper_t*)ptr;
    if (wrapper) {
        if (wrapper->prepared) {
            cass_prepared_free(wrapper->prepared);
        }
        xfree(wrapper);
    }
}

const rb_data_type_t prepared_statement_type = {
    "CassandraCpp::NativePreparedStatement",
    { 0, prepared_statement_free, 0 },
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

// Prepared statement methods
static VALUE prepared_statement_bind(VALUE self) {
    prepared_statement_wrapper_t* prepared_wrapper;
    TypedData_Get_Struct(self, prepared_statement_wrapper_t, &prepared_statement_type, prepared_wrapper);
    
    // Create statement from prepared
    CassStatement* statement = cass_prepared_bind(prepared_wrapper->prepared);
    
    // Create statement wrapper
    statement_wrapper_t* statement_wrapper = ALLOC(statement_wrapper_t);
    statement_wrapper->statement = statement;
    statement_wrapper->prepared = prepared_wrapper->prepared;
    statement_wrapper->prepared_ref = self;
    
    VALUE statement_obj = TypedData_Wrap_Struct(rb_cStatement, &statement_type, statement_wrapper);
    
    // Keep reference to prevent prepared statement from being GC'd
    rb_iv_set(statement_obj, "@prepared_statement", self);
    
    return statement_obj;
}

void init_prepared_statement() {
    rb_cPreparedStatement = rb_define_class_under(rb_cCassandraCpp, "NativePreparedStatement", rb_cObject);
    rb_undef_alloc_func(rb_cPreparedStatement);
    rb_define_method(rb_cPreparedStatement, "bind", (VALUE(*)(...))prepared_statement_bind, 0);
}
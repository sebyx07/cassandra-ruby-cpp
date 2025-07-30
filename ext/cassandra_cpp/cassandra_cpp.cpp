#include "cassandra_cpp.h"

// Module initialization
extern "C" void Init_cassandra_cpp() {
    // Main module
    rb_cCassandraCpp = rb_define_module("CassandraCpp");
    
    // Exception class
    rb_eCassandraError = rb_define_class_under(rb_cCassandraCpp, "Error", rb_eStandardError);
    
    // Initialize classes
    init_cluster();
    init_session();
    init_prepared_statement();
    init_statement();
    init_batch();
    init_future();
    
    // Constants for consistency levels
    rb_define_const(rb_cCassandraCpp, "CONSISTENCY_ANY", INT2NUM(CASS_CONSISTENCY_ANY));
    rb_define_const(rb_cCassandraCpp, "CONSISTENCY_ONE", INT2NUM(CASS_CONSISTENCY_ONE));
    rb_define_const(rb_cCassandraCpp, "CONSISTENCY_TWO", INT2NUM(CASS_CONSISTENCY_TWO));
    rb_define_const(rb_cCassandraCpp, "CONSISTENCY_THREE", INT2NUM(CASS_CONSISTENCY_THREE));
    rb_define_const(rb_cCassandraCpp, "CONSISTENCY_QUORUM", INT2NUM(CASS_CONSISTENCY_QUORUM));
    rb_define_const(rb_cCassandraCpp, "CONSISTENCY_ALL", INT2NUM(CASS_CONSISTENCY_ALL));
    rb_define_const(rb_cCassandraCpp, "CONSISTENCY_LOCAL_QUORUM", INT2NUM(CASS_CONSISTENCY_LOCAL_QUORUM));
    rb_define_const(rb_cCassandraCpp, "CONSISTENCY_EACH_QUORUM", INT2NUM(CASS_CONSISTENCY_EACH_QUORUM));
    rb_define_const(rb_cCassandraCpp, "CONSISTENCY_SERIAL", INT2NUM(CASS_CONSISTENCY_SERIAL));
    rb_define_const(rb_cCassandraCpp, "CONSISTENCY_LOCAL_SERIAL", INT2NUM(CASS_CONSISTENCY_LOCAL_SERIAL));
    rb_define_const(rb_cCassandraCpp, "CONSISTENCY_LOCAL_ONE", INT2NUM(CASS_CONSISTENCY_LOCAL_ONE));
    
    // Constants for batch types
    rb_define_const(rb_cCassandraCpp, "BATCH_TYPE_LOGGED", INT2NUM(CASS_BATCH_TYPE_LOGGED));
    rb_define_const(rb_cCassandraCpp, "BATCH_TYPE_UNLOGGED", INT2NUM(CASS_BATCH_TYPE_UNLOGGED));
    rb_define_const(rb_cCassandraCpp, "BATCH_TYPE_COUNTER", INT2NUM(CASS_BATCH_TYPE_COUNTER));
}
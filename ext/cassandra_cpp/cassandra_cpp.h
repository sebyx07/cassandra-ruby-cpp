#ifndef CASSANDRA_CPP_H
#define CASSANDRA_CPP_H

#include <ruby.h>
#include <cassandra.h>
#include <string>
#include <memory>

// Forward declarations of Ruby classes
extern VALUE rb_cCassandraCpp;
extern VALUE rb_cCluster;
extern VALUE rb_cSession;
extern VALUE rb_cPreparedStatement;
extern VALUE rb_cStatement;
extern VALUE rb_eCassandraError;

// Wrapper structures
typedef struct {
    CassCluster* cluster;
    CassFuture* connect_future;
    CassSession* session;
} cluster_wrapper_t;

typedef struct {
    CassSession* session;
    VALUE cluster_ref;
} session_wrapper_t;

typedef struct {
    const CassPrepared* prepared;
    VALUE session_ref;
} prepared_statement_wrapper_t;

typedef struct {
    CassStatement* statement;
    const CassPrepared* prepared; // For parameter binding validation
    VALUE prepared_ref;
} statement_wrapper_t;

// Type information
extern const rb_data_type_t cluster_type;
extern const rb_data_type_t session_type;
extern const rb_data_type_t prepared_statement_type;
extern const rb_data_type_t statement_type;

// Helper functions
void raise_cassandra_error(CassFuture* future, const char* operation);
VALUE convert_cass_value_to_ruby(const CassValue* value);

// Initialization functions
void init_cluster();
void init_session();
void init_prepared_statement();
void init_statement();

#endif // CASSANDRA_CPP_H
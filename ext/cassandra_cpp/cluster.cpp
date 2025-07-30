#include "cassandra_cpp.h"

// Memory management functions
static void cluster_free(void* ptr) {
    cluster_wrapper_t* wrapper = (cluster_wrapper_t*)ptr;
    if (wrapper) {
        if (wrapper->session) {
            cass_session_free(wrapper->session);
        }
        if (wrapper->connect_future) {
            cass_future_free(wrapper->connect_future);
        }
        if (wrapper->cluster) {
            cass_cluster_free(wrapper->cluster);
        }
        xfree(wrapper);
    }
}

const rb_data_type_t cluster_type = {
    "CassandraCpp::NativeCluster",
    { 0, cluster_free, 0 },
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

// Cluster methods
static VALUE cluster_new(VALUE klass, VALUE options) {
    cluster_wrapper_t* wrapper = ALLOC(cluster_wrapper_t);
    wrapper->cluster = cass_cluster_new();
    wrapper->connect_future = NULL;
    wrapper->session = NULL;
    
    // Set defaults
    const char* default_hosts = "127.0.0.1";  // Will be overridden by options
    int default_port = 9042;
    
    // Configure options if provided
    if (!NIL_P(options)) {
        Check_Type(options, T_HASH);
        
        VALUE hosts = rb_hash_aref(options, ID2SYM(rb_intern("hosts")));
        if (!NIL_P(hosts)) {
            const char* hosts_str = StringValueCStr(hosts);
            cass_cluster_set_contact_points(wrapper->cluster, hosts_str);
        } else {
            cass_cluster_set_contact_points(wrapper->cluster, default_hosts);
        }
        
        VALUE port = rb_hash_aref(options, ID2SYM(rb_intern("port")));
        if (!NIL_P(port)) {
            int port_num = NUM2INT(port);
            cass_cluster_set_port(wrapper->cluster, port_num);
        } else {
            cass_cluster_set_port(wrapper->cluster, default_port);
        }
        
        VALUE consistency = rb_hash_aref(options, ID2SYM(rb_intern("consistency")));
        if (!NIL_P(consistency)) {
            int consistency_level = NUM2INT(consistency);
            cass_cluster_set_consistency(wrapper->cluster, (CassConsistency)consistency_level);
        }
    } else {
        // No options provided, use defaults
        cass_cluster_set_contact_points(wrapper->cluster, default_hosts);
        cass_cluster_set_port(wrapper->cluster, default_port);
    }
    
    return TypedData_Wrap_Struct(klass, &cluster_type, wrapper);
}

static VALUE cluster_connect(int argc, VALUE* argv, VALUE self) {
    VALUE keyspace;
    rb_scan_args(argc, argv, "01", &keyspace);
    
    cluster_wrapper_t* cluster;
    TypedData_Get_Struct(self, cluster_wrapper_t, &cluster_type, cluster);
    
    // Create session
    cluster->session = cass_session_new();
    
    // Connect to cluster
    if (NIL_P(keyspace)) {
        cluster->connect_future = cass_session_connect(cluster->session, cluster->cluster);
    } else {
        const char* keyspace_str = StringValueCStr(keyspace);
        cluster->connect_future = cass_session_connect_keyspace(cluster->session, cluster->cluster, keyspace_str);
    }
    
    // Wait for connection
    CassError rc = cass_future_error_code(cluster->connect_future);
    if (rc != CASS_OK) {
        raise_cassandra_error(cluster->connect_future, "connection");
    }
    
    // Create session wrapper
    session_wrapper_t* session_wrapper = ALLOC(session_wrapper_t);
    session_wrapper->session = cluster->session;
    session_wrapper->cluster_ref = self;
    
    VALUE session_obj = TypedData_Wrap_Struct(rb_cSession, &session_type, session_wrapper);
    
    // Keep reference to prevent cluster from being GC'd
    rb_iv_set(session_obj, "@cluster", self);
    
    return session_obj;
}

void init_cluster() {
    rb_cCluster = rb_define_class_under(rb_cCassandraCpp, "NativeCluster", rb_cObject);
    rb_undef_alloc_func(rb_cCluster);
    rb_define_singleton_method(rb_cCluster, "new", (VALUE(*)(...))cluster_new, 1);
    rb_define_method(rb_cCluster, "connect", (VALUE(*)(...))cluster_connect, -1);
}
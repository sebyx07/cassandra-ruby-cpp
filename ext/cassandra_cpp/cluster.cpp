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
        
        // Connection pool configuration
        VALUE core_connections = rb_hash_aref(options, ID2SYM(rb_intern("core_connections_per_host")));
        if (!NIL_P(core_connections)) {
            unsigned int core_conn = NUM2UINT(core_connections);
            cass_cluster_set_core_connections_per_host(wrapper->cluster, core_conn);
        }
        
        VALUE max_connections = rb_hash_aref(options, ID2SYM(rb_intern("max_connections_per_host")));
        if (!NIL_P(max_connections)) {
            unsigned int max_conn = NUM2UINT(max_connections);
            cass_cluster_set_max_connections_per_host(wrapper->cluster, max_conn);
        }
        
        VALUE concurrent_requests = rb_hash_aref(options, ID2SYM(rb_intern("max_concurrent_requests_threshold")));
        if (!NIL_P(concurrent_requests)) {
            unsigned int max_req = NUM2UINT(concurrent_requests);
            cass_cluster_set_max_concurrent_requests_threshold(wrapper->cluster, max_req);
        }
        
        VALUE connect_timeout = rb_hash_aref(options, ID2SYM(rb_intern("connect_timeout")));
        if (!NIL_P(connect_timeout)) {
            unsigned int timeout_ms = NUM2UINT(connect_timeout);
            cass_cluster_set_connect_timeout(wrapper->cluster, timeout_ms);
        }
        
        VALUE request_timeout = rb_hash_aref(options, ID2SYM(rb_intern("request_timeout")));
        if (!NIL_P(request_timeout)) {
            unsigned int timeout_ms = NUM2UINT(request_timeout);
            cass_cluster_set_request_timeout(wrapper->cluster, timeout_ms);
        }
        
        // Load balancing configuration
        VALUE load_balance_policy = rb_hash_aref(options, ID2SYM(rb_intern("load_balance_policy")));
        if (!NIL_P(load_balance_policy)) {
            const char* policy_str = StringValueCStr(load_balance_policy);
            if (strcmp(policy_str, "round_robin") == 0) {
                cass_cluster_set_load_balance_round_robin(wrapper->cluster);
            } else if (strcmp(policy_str, "dc_aware") == 0) {
                VALUE local_dc = rb_hash_aref(options, ID2SYM(rb_intern("local_datacenter")));
                VALUE used_hosts_remote = rb_hash_aref(options, ID2SYM(rb_intern("used_hosts_per_remote_dc")));
                VALUE allow_remote = rb_hash_aref(options, ID2SYM(rb_intern("allow_remote_dcs_for_local_cl")));
                
                const char* local_dc_str = NIL_P(local_dc) ? NULL : StringValueCStr(local_dc);
                unsigned int used_hosts = NIL_P(used_hosts_remote) ? 0 : NUM2UINT(used_hosts_remote);
                cass_bool_t allow_remote_bool = NIL_P(allow_remote) ? cass_false : (RTEST(allow_remote) ? cass_true : cass_false);
                
                if (local_dc_str) {
                    cass_cluster_set_load_balance_dc_aware(wrapper->cluster, local_dc_str, used_hosts, allow_remote_bool);
                } else {
                    cass_cluster_set_load_balance_dc_aware(wrapper->cluster, NULL, used_hosts, allow_remote_bool);
                }
            }
        }
        
        // Token-aware routing
        VALUE token_aware = rb_hash_aref(options, ID2SYM(rb_intern("token_aware_routing")));
        if (!NIL_P(token_aware)) {
            cass_bool_t enabled = RTEST(token_aware) ? cass_true : cass_false;
            cass_cluster_set_token_aware_routing(wrapper->cluster, enabled);
        }
        
        // Latency-aware routing
        VALUE latency_aware = rb_hash_aref(options, ID2SYM(rb_intern("latency_aware_routing")));
        if (!NIL_P(latency_aware)) {
            cass_bool_t enabled = RTEST(latency_aware) ? cass_true : cass_false;
            cass_cluster_set_latency_aware_routing(wrapper->cluster, enabled);
            
            if (enabled) {
                VALUE exclusion_threshold = rb_hash_aref(options, ID2SYM(rb_intern("latency_exclusion_threshold")));
                VALUE scale_ms = rb_hash_aref(options, ID2SYM(rb_intern("latency_scale_ms")));
                VALUE retry_period_ms = rb_hash_aref(options, ID2SYM(rb_intern("latency_retry_period_ms")));
                VALUE update_rate_ms = rb_hash_aref(options, ID2SYM(rb_intern("latency_update_rate_ms")));
                VALUE min_measured = rb_hash_aref(options, ID2SYM(rb_intern("latency_min_measured")));
                
                if (!NIL_P(exclusion_threshold) || !NIL_P(scale_ms) || !NIL_P(retry_period_ms) || 
                    !NIL_P(update_rate_ms) || !NIL_P(min_measured)) {
                    cass_double_t threshold = NIL_P(exclusion_threshold) ? 2.0 : NUM2DBL(exclusion_threshold);
                    cass_uint64_t scale = NIL_P(scale_ms) ? 100 : NUM2ULL(scale_ms);
                    cass_uint64_t retry_period = NIL_P(retry_period_ms) ? 10000 : NUM2ULL(retry_period_ms);
                    cass_uint64_t update_rate = NIL_P(update_rate_ms) ? 100 : NUM2ULL(update_rate_ms);
                    cass_uint64_t min_measured_queries = NIL_P(min_measured) ? 50 : NUM2ULL(min_measured);
                    
                    cass_cluster_set_latency_aware_routing_settings(wrapper->cluster, threshold, 
                        scale, retry_period, update_rate, min_measured_queries);
                }
            }
        }
        
        // Retry policy configuration
        VALUE retry_policy = rb_hash_aref(options, ID2SYM(rb_intern("retry_policy")));
        if (!NIL_P(retry_policy)) {
            const char* policy_str = StringValueCStr(retry_policy);
            CassRetryPolicy* policy = NULL;
            
            if (strcmp(policy_str, "default") == 0) {
                policy = cass_retry_policy_default_new();
            } else if (strcmp(policy_str, "downgrading_consistency") == 0) {
                policy = cass_retry_policy_downgrading_consistency_new();
            } else if (strcmp(policy_str, "fallthrough") == 0) {
                policy = cass_retry_policy_fallthrough_new();
            }
            
            if (policy) {
                VALUE logging_enabled = rb_hash_aref(options, ID2SYM(rb_intern("retry_policy_logging")));
                if (!NIL_P(logging_enabled) && RTEST(logging_enabled)) {
                    CassRetryPolicy* logging_policy = cass_retry_policy_logging_new(policy);
                    cass_cluster_set_retry_policy(wrapper->cluster, logging_policy);
                    cass_retry_policy_free(logging_policy);
                } else {
                    cass_cluster_set_retry_policy(wrapper->cluster, policy);
                }
                cass_retry_policy_free(policy);
            }
        }
        
        // Heartbeat interval
        VALUE heartbeat_interval = rb_hash_aref(options, ID2SYM(rb_intern("heartbeat_interval")));
        if (!NIL_P(heartbeat_interval)) {
            unsigned int interval_s = NUM2UINT(heartbeat_interval);
            cass_cluster_set_connection_heartbeat_interval(wrapper->cluster, interval_s);
        }
        
        // Idle timeout
        VALUE idle_timeout = rb_hash_aref(options, ID2SYM(rb_intern("connection_idle_timeout")));
        if (!NIL_P(idle_timeout)) {
            unsigned int timeout_s = NUM2UINT(idle_timeout);
            cass_cluster_set_connection_idle_timeout(wrapper->cluster, timeout_s);
        }
    } else {
        // No options provided, use defaults
        cass_cluster_set_contact_points(wrapper->cluster, default_hosts);
        cass_cluster_set_port(wrapper->cluster, default_port);
        
        // Set sensible defaults for connection pooling
        cass_cluster_set_core_connections_per_host(wrapper->cluster, 1);
        cass_cluster_set_max_connections_per_host(wrapper->cluster, 2);
        cass_cluster_set_max_concurrent_requests_threshold(wrapper->cluster, 100);
        cass_cluster_set_connect_timeout(wrapper->cluster, 5000); // 5 seconds
        cass_cluster_set_request_timeout(wrapper->cluster, 12000); // 12 seconds
        cass_cluster_set_token_aware_routing(wrapper->cluster, cass_true);
        cass_cluster_set_connection_heartbeat_interval(wrapper->cluster, 30); // 30 seconds
        cass_cluster_set_connection_idle_timeout(wrapper->cluster, 60); // 60 seconds
        
        // Set default retry policy
        CassRetryPolicy* default_policy = cass_retry_policy_default_new();
        cass_cluster_set_retry_policy(wrapper->cluster, default_policy);
        cass_retry_policy_free(default_policy);
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
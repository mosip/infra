#!/bin/bash

# Configuration options
# Set to "true" to continue to the next namespace even if jobs in the current namespace fail
CONTINUE_ON_FAILURE=${CONTINUE_ON_FAILURE:-"true"}
# Set to "true" to collect all failures and report them at the end instead of exiting immediately
COLLECT_ALL_FAILURES=${COLLECT_ALL_FAILURES:-"false"}
# Set timeout in seconds for waiting for a job to complete (default: 1.5 hours = 5400 seconds)
JOB_TIMEOUT=${JOB_TIMEOUT:-5400}
# Set timeout for an entire namespace's jobs (default: 1.5hrs minutes)
NAMESPACE_TIMEOUT=${NAMESPACE_TIMEOUT:-10800}

# Global variables
FAILED_JOBS=()
TIMED_OUT_JOBS=()

# Function to trigger all CronJobs in a namespace SEQUENTIALLY
trigger_all_cronjobs_in_namespace() {
    namespace=$1
    echo "Triggering all CronJobs in namespace: $namespace"
    
    local cronjobs
    
    # Define specific order for apitestrig namespace
    if [[ "$namespace" == "apitestrig" ]]; then
        # Use predefined order for apitestrig
        cronjobs="cronjob-apitestrig-partner cronjob-apitestrig-idrepo cronjob-apitestrig-masterdata cronjob-apitestrig-auth cronjob-apitestrig-prereg cronjob-apitestrig-resident"
        echo "Using predefined order for apitestrig namespace"
    else
        # Get all CronJobs in the namespace for other namespaces
        cronjobs=$(kubectl get cronjobs -n $namespace -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
        
        if [[ $? -ne 0 || -z "$cronjobs" ]]; then
            echo "WARNING: No CronJobs found in namespace $namespace or could not access namespace"
            return 0
        fi
    fi
    
    local all_succeeded=true
    local namespace_start_time=$(date +%s)
    
    # Process each CronJob sequentially
    for cronjob in $cronjobs; do
        # Check if cronjob exists before creating job
        if ! kubectl get cronjob -n $namespace $cronjob &>/dev/null; then
            echo "WARNING: CronJob $cronjob not found in namespace $namespace, skipping..."
            continue
        fi
        
        # Check if we've exceeded the namespace timeout
        local current_time=$(date +%s)
        local namespace_elapsed_time=$((current_time - namespace_start_time))
        
        if [[ $namespace_elapsed_time -gt $NAMESPACE_TIMEOUT ]]; then
            echo "WARNING: Namespace $namespace has exceeded timeout of ${NAMESPACE_TIMEOUT} seconds"
            echo "Remaining cronjobs will be skipped: $cronjob"
            TIMED_OUT_JOBS+=("$namespace/$cronjob (NAMESPACE TIMEOUT - SKIPPED)")
            all_succeeded=false
            break
        fi
        
        job_name="${cronjob}-manual-$(date +%s-%N)"
        echo "Creating job $job_name from cronjob $cronjob"
        
        # Create a job from the cronjob
        if ! kubectl create job -n $namespace $job_name --from=cronjob/$cronjob 2>/dev/null; then
            echo "WARNING: Failed to create job from cronjob $cronjob"
            FAILED_JOBS+=("$namespace/$cronjob (CREATION FAILED)")
            all_succeeded=false
            continue
        fi
        
        # Wait for this specific job to complete before moving to the next
        local result
        wait_for_single_job $namespace result "$job_name"
        
        if [[ $result -ne 0 ]]; then
            all_succeeded=false
            echo "Job $job_name failed or timed out"
            
            # Check if we should continue or exit
            if [[ "$COLLECT_ALL_FAILURES" != "true" && "$CONTINUE_ON_FAILURE" != "true" ]]; then
                echo "Exiting due to job failure"
                return 1
            fi
        else
            echo "Job $job_name completed successfully"
        fi
        
        echo "--- Moving to next cronjob ---"
    done
    
    if [[ "$all_succeeded" == "true" ]]; then
        echo "All cronjobs in namespace $namespace have completed successfully"
        return 0
    else
        echo "WARNING: Some cronjobs in namespace $namespace failed or timed out"
        return 1
    fi
}

# Function to wait for a single job to complete
wait_for_single_job() {
    local namespace=$1
    local -n result_var=$2
    local job_name=$3
    
    echo "Waiting for job $job_name to complete in namespace $namespace"
    
    local job_start_time=$(date +%s)
    
    # Keep checking until job is done or we hit the job timeout
    while true; do
        local current_time=$(date +%s)
        local job_elapsed_time=$((current_time - job_start_time))
        
        # Check if we've exceeded the job timeout
        if [[ $job_elapsed_time -gt $JOB_TIMEOUT ]]; then
            echo "ERROR: Job $job_name timed out after ${job_elapsed_time} seconds"
            FAILED_JOBS+=("$namespace/$job_name (TIMEOUT)")
            
            # Try to get logs from the timed out job
            local pod_name=$(kubectl get pods -n $namespace -l job-name=$job_name -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            if [[ -n "$pod_name" ]]; then
                echo "Last 50 lines of logs for timed out job pod $pod_name:"
                kubectl logs -n $namespace $pod_name --tail=50 2>/dev/null || echo "Could not retrieve logs"
            fi
            
            result_var=1
            return 1
        fi
        
        # Check if job exists
        local job_exists=$(kubectl get job -n $namespace $job_name -o name 2>/dev/null || echo "")
        
        if [[ -z "$job_exists" ]]; then
            echo "WARNING: Job $job_name no longer exists in namespace $namespace"
            FAILED_JOBS+=("$namespace/$job_name (NOT FOUND)")
            result_var=1
            return 1
        fi
        
        local job_status=$(kubectl get job -n $namespace $job_name -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
        local job_failed=$(kubectl get job -n $namespace $job_name -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
        
        if [[ "$job_status" == "True" ]]; then
            echo "Job $job_name completed successfully after ${job_elapsed_time} seconds"
            result_var=0
            return 0
        elif [[ "$job_failed" == "True" ]]; then
            echo "ERROR: Job $job_name failed after ${job_elapsed_time} seconds"
            FAILED_JOBS+=("$namespace/$job_name")
            
            # Get pod logs for the failed job
            local pod_name=$(kubectl get pods -n $namespace -l job-name=$job_name -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            if [[ -n "$pod_name" ]]; then
                echo "Last 50 lines of logs for failed job pod $pod_name:"
                kubectl logs -n $namespace $pod_name --tail=50 2>/dev/null || echo "Could not retrieve logs"
            fi
            
            result_var=1
            return 1
        else
            # Job is still running
            echo "Job $job_name still running, checking again in 10 seconds... (${job_elapsed_time}s elapsed)"
            sleep 10
        fi
    done
}

# Function to trigger a specific CronJob in the dslrig namespace
trigger_specific_dsl_cronjob() {
    namespace="dslrig"
    cronjob="cronjob-dslorchestrator-sanity"
    
    echo "Triggering specific CronJob in namespace $namespace: $cronjob"
    
    # Check if the cronjob exists
    if kubectl get cronjob -n $namespace $cronjob &>/dev/null; then
        job_name="${cronjob}-manual-$(date +%s-%N)"
        echo "Creating job $job_name from cronjob $cronjob"
        
        # Create a job from the cronjob
        kubectl create job -n $namespace $job_name --from=cronjob/$cronjob
        
        # Wait for the job to complete
        local result
        wait_for_single_job $namespace result "$job_name"
        return $result
    else
        echo "ERROR: CronJob $cronjob not found in namespace $namespace"
        if [[ "$CONTINUE_ON_FAILURE" == "true" ]]; then
            return 1
        else
            exit 1
        fi
    fi
}

# Function to wait for jobs to complete (kept for uitestrig namespace compatibility)
wait_for_jobs() {
    local namespace=$1
    local -n result_var=$2
    shift 2
    local job_names=("$@")
    
    echo "Waiting for jobs to complete in namespace $namespace: ${job_names[*]}"
    
    local all_succeeded=true
    local failures=0
    local namespace_start_time=$(date +%s)
    local unfinished_jobs=("${job_names[@]}")
    
    # Keep checking until all jobs are done or we hit the namespace timeout
    while [[ ${#unfinished_jobs[@]} -gt 0 ]]; do
        local current_time=$(date +%s)
        local namespace_elapsed_time=$((current_time - namespace_start_time))
        
        # Check if we've exceeded the namespace timeout
        if [[ $namespace_elapsed_time -gt $NAMESPACE_TIMEOUT ]]; then
            echo "WARNING: Namespace $namespace has exceeded timeout of ${NAMESPACE_TIMEOUT} seconds"
            echo "The following jobs are still running and will be marked as timed out:"
            
            for job in "${unfinished_jobs[@]}"; do
                echo "  - $job"
                TIMED_OUT_JOBS+=("$namespace/$job (NAMESPACE TIMEOUT)")
            done
            
            all_succeeded=false
            break
        fi
        
        # Create a new array to hold jobs that are still unfinished after this round
        local still_unfinished=()
        
        for job_name in "${unfinished_jobs[@]}"; do
            # Skip jobs that we've already determined are finished
            local job_exists=$(kubectl get job -n $namespace $job_name -o name 2>/dev/null || echo "")
            
            if [[ -z "$job_exists" ]]; then
                echo "WARNING: Job $job_name no longer exists in namespace $namespace"
                all_succeeded=false
                failures=$((failures + 1))
                FAILED_JOBS+=("$namespace/$job_name (NOT FOUND)")
                continue
            fi
            
            local job_status=$(kubectl get job -n $namespace $job_name -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
            local job_failed=$(kubectl get job -n $namespace $job_name -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
            
            # Get the creation timestamp to calculate job-specific elapsed time
            local job_start_time=$(kubectl get job -n $namespace $job_name -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "")
            if [[ -n "$job_start_time" ]]; then
                job_start_seconds=$(date -d "$job_start_time" +%s 2>/dev/null || echo "0")
                local job_elapsed_time=$((current_time - job_start_seconds))
            else
                local job_elapsed_time=0
            fi
            
            if [[ "$job_status" == "True" ]]; then
                echo "Job $job_name completed successfully"
                # This job is done, so we don't add it to still_unfinished
            elif [[ "$job_failed" == "True" ]]; then
                echo "ERROR: Job $job_name failed"
                all_succeeded=false
                failures=$((failures + 1))
                FAILED_JOBS+=("$namespace/$job_name")
                
                # Get pod logs for the failed job
                local pod_name=$(kubectl get pods -n $namespace -l job-name=$job_name -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
                if [[ -n "$pod_name" ]]; then
                    echo "Last 50 lines of logs for failed job pod $pod_name:"
                    kubectl logs -n $namespace $pod_name --tail=50 2>/dev/null || echo "Could not retrieve logs"
                fi
                # This job is done (failed), so we don't add it to still_unfinished
            elif [[ $job_elapsed_time -gt $JOB_TIMEOUT ]]; then
                echo "ERROR: Job $job_name timed out after ${job_elapsed_time} seconds"
                all_succeeded=false
                failures=$((failures + 1))
                FAILED_JOBS+=("$namespace/$job_name (TIMEOUT)")
                
                # Try to get logs from the timed out job
                local pod_name=$(kubectl get pods -n $namespace -l job-name=$job_name -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
                if [[ -n "$pod_name" ]]; then
                    echo "Last 50 lines of logs for timed out job pod $pod_name:"
                    kubectl logs -n $namespace $pod_name --tail=50 2>/dev/null || echo "Could not retrieve logs"
                fi
                
                # This job is done (timed out), so we don't add it to still_unfinished
            else
                # Job is still running, add it to still_unfinished
                still_unfinished+=("$job_name")
                echo "Job $job_name still running, checking again in 10 seconds... (${job_elapsed_time}s elapsed)"
            fi
        done
        
        # Update our list of unfinished jobs
        unfinished_jobs=("${still_unfinished[@]}")
        
        # If we still have unfinished jobs, wait before checking again
        if [[ ${#unfinished_jobs[@]} -gt 0 ]]; then
            sleep 10
        fi
    done
    
    if [[ "$all_succeeded" == "true" ]]; then
        echo "All jobs in namespace $namespace have completed successfully"
        result_var=0
        return 0
    else
        echo "WARNING: $failures job(s) in namespace $namespace failed or timed out"
        result_var=1
        
        if [[ "$COLLECT_ALL_FAILURES" != "true" && "$CONTINUE_ON_FAILURE" != "true" ]]; then
            echo "Exiting due to job failures"
            exit 1
        fi
        
        return 1
    fi
}

# Main execution
echo "Starting sequential test execution across namespaces"

# Track overall success
OVERALL_SUCCESS=true

# Step 1: Trigger specific CronJob in dslrig namespace FIRST
echo "=== STEP 1: Processing dslrig namespace ==="
trigger_specific_dsl_cronjob
dslrig_result=$?

if [[ $dslrig_result -ne 0 ]]; then
    echo "WARNING: Specific job in dslrig namespace failed or timed out"
    OVERALL_SUCCESS=false
    if [[ "$CONTINUE_ON_FAILURE" != "true" ]]; then
        echo "Exiting due to failure in dslrig namespace"
        
        # Report failures
        if [[ ${#FAILED_JOBS[@]} -gt 0 ]]; then
            echo "Failed jobs:"
            for job in "${FAILED_JOBS[@]}"; do
                echo "  - $job"
            done
        fi
        
        # Report timed out jobs
        if [[ ${#TIMED_OUT_JOBS[@]} -gt 0 ]]; then
            echo "Timed out jobs:"
            for job in "${TIMED_OUT_JOBS[@]}"; do
                echo "  - $job"
            done
        fi
        
        exit 1
    fi
else
    echo "Specific job in dslrig namespace completed successfully"
fi

# Step 2: Trigger all CronJobs in apitestrig namespace SEQUENTIALLY in specified order
echo "=== STEP 2: Processing apitestrig namespace (SEQUENTIAL - SPECIFIC ORDER) ==="
trigger_all_cronjobs_in_namespace "apitestrig"
apitestrig_result=$?

if [[ $apitestrig_result -ne 0 ]]; then
    echo "WARNING: Some jobs in apitestrig namespace failed or timed out"
    OVERALL_SUCCESS=false
    if [[ "$CONTINUE_ON_FAILURE" != "true" ]]; then
        echo "Exiting due to failures in apitestrig namespace"
        
        # Report failures
        if [[ ${#FAILED_JOBS[@]} -gt 0 ]]; then
            echo "Failed jobs:"
            for job in "${FAILED_JOBS[@]}"; do
                echo "  - $job"
            done
        fi
        
        # Report timed out jobs
        if [[ ${#TIMED_OUT_JOBS[@]} -gt 0 ]]; then
            echo "Timed out jobs:"
            for job in "${TIMED_OUT_JOBS[@]}"; do
                echo "  - $job"
            done
        fi
        
        exit 1
    fi
else
    echo "All jobs in apitestrig namespace completed successfully"
fi

# Step 3: Trigger all CronJobs in uitestrig 10800namespace
echo "=== STEP 3: Processing uitestrig namespace ==="
trigger_all_cronjobs_in_namespace "uitestrig"
uitestrig_result=$?

if [[ $uitestrig_result -ne 0 ]]; then
    echo "WARNING: Some jobs in uitestrig namespace failed or timed out"
    OVERALL_SUCCESS=false
else
    echo "All jobs in uitestrig namespace completed successfully"
fi

# Final report
echo ""
echo "=== EXECUTION SUMMARY ==="
if [[ "$OVERALL_SUCCESS" == "true" ]]; then
    echo "All namespaces processed successfully"
    exit_code=0
else
    echo "There were failures during execution"
    
    # Report all collected failures
    if [[ ${#FAILED_JOBS[@]} -gt 0 ]]; then
        echo "Failed jobs:"
        for job in "${FAILED_JOBS[@]}"; do
            echo "  - $job"
        done
    fi
    
    # Report all timed out jobs
    if [[ ${#TIMED_OUT_JOBS[@]} -gt 0 ]]; then
        echo "Timed out jobs:"
        for job in "${TIMED_OUT_JOBS[@]}"; do
            echo "  - $job"
        done
    fi
    
    exit_code=1
fi

exit $exit_code
#!/bin/bash
# ============================================================================
# Kubernetes Namespace Cleanup Script
# ============================================================================
# This script forcefully removes Kubernetes namespaces that are stuck in
# "Terminating" state by removing their finalizers.
#
# Usage: ./cleanup-namespaces.sh [namespace1] [namespace2] ...
# If no namespaces are provided, it will find all terminating namespaces.
#
# Example:
#   ./cleanup-namespaces.sh monitoring logging argocd
#   ./cleanup-namespaces.sh  # Finds all terminating namespaces automatically
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to remove finalizers from a namespace
cleanup_namespace() {
    local namespace=$1

    echo -e "${YELLOW}Cleaning up namespace: ${namespace}${NC}"

    # Check if namespace exists
    if ! kubectl get namespace "${namespace}" &>/dev/null; then
        echo -e "${RED}Namespace ${namespace} does not exist${NC}"
        return 1
    fi

    # Check if namespace is terminating
    local status=$(kubectl get namespace "${namespace}" -o jsonpath='{.status.phase}')
    if [[ "${status}" != "Terminating" ]]; then
        echo -e "${YELLOW}Namespace ${namespace} is not in Terminating state (current: ${status})${NC}"
        return 0
    fi

    # Remove finalizers
    echo "Removing finalizers from namespace ${namespace}..."
    kubectl get namespace "${namespace}" -o json | \
        jq '.spec.finalizers = null' > /tmp/"${namespace}".json

    kubectl replace --raw "/api/v1/namespaces/${namespace}/finalize" \
        -f /tmp/"${namespace}".json &>/dev/null

    # Cleanup temp file
    rm -f /tmp/"${namespace}".json

    echo -e "${GREEN}✓ Successfully cleaned up namespace: ${namespace}${NC}"
}

# Main script
main() {
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed${NC}"
        exit 1
    fi

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is not installed${NC}"
        exit 1
    fi

    # Check if connected to cluster
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}Error: Not connected to any Kubernetes cluster${NC}"
        exit 1
    fi

    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Kubernetes Namespace Cleanup Script${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""

    # If no arguments provided, find all terminating namespaces
    if [ $# -eq 0 ]; then
        echo "Finding all terminating namespaces..."
        mapfile -t namespaces < <(kubectl get namespaces -o json | \
            jq -r '.items[] | select(.status.phase=="Terminating") | .metadata.name')

        if [ ${#namespaces[@]} -eq 0 ]; then
            echo -e "${GREEN}No terminating namespaces found${NC}"
            exit 0
        fi

        echo -e "${YELLOW}Found ${#namespaces[@]} terminating namespace(s):${NC}"
        printf '%s\n' "${namespaces[@]}"
        echo ""

        read -p "Do you want to clean up all these namespaces? (yes/no): " confirm
        if [[ ! "${confirm}" =~ ^(yes|y|Y)$ ]]; then
            echo "Aborted"
            exit 0
        fi
    else
        namespaces=("$@")
    fi

    # Process each namespace
    failed_namespaces=()
    for ns in "${namespaces[@]}"; do
        if ! cleanup_namespace "${ns}"; then
            failed_namespaces+=("${ns}")
        fi
    done

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Cleanup Summary${NC}"
    echo -e "${GREEN}============================================${NC}"

    if [ ${#failed_namespaces[@]} -eq 0 ]; then
        echo -e "${GREEN}All namespaces cleaned up successfully!${NC}"
        exit 0
    else
        echo -e "${RED}Failed to clean up ${#failed_namespaces[@]} namespace(s):${NC}"
        printf '%s\n' "${failed_namespaces[@]}"
        exit 1
    fi
}

# Run main function
main "$@"

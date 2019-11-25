# Kubernetes + Hashicorp Vault Integration Demo

## Enable Kubernetes to Vault Authentication

This is a one-time process to enable Vault to validate Kubernetes service account tokens

### On the Kubernetes Cluster

1. Create a service account for Vault to use to verify tokens

    ```    
    kubectl create serviceaccount vault-auth
    ```

2. Create a ClusterRoleBinding to grant the vault-auth service account permissions to verify
   tokens

   ```
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: role-tokenreview-binding
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: system:auth-delegator
   subjects:
   - kind: ServiceAccount
     name: vault-auth
     namespace: default
   ```

3. Retrieve Service Account Token

    ```
    export SECRET_NAME=$(kubectl get sa vault-auth -o jsonpath='{.secrets[0].name}')
    kubectl get secret ${SECRET_NAME} -o jsonpath='{.data.token}' | base64 --decode
    ```

### On the Vault Server

1. Enable the Kubernetes Authentication Plugin

    ```
    vault auth enable kubernetes
    ```

2. Configure the Kubernetes Authentication Plugin
    - Replace <kubernetes_service_account_jwt> with vault-auth's service account token.
    - Replace <kubernetes_api_address> with the Kubernetes API hostname.
    - ca.crt is the CA certificate for the Kubernetes API

    ```
    vault write auth/kubernetes/config \
        token_reviewer_jwt="<kubernetes_service_account_jwt>" \
        kubernetes_host="<kubernetes_api_address>" \
        kubernetes_ca_cert=@ca.crt
    ```

## Test Authentication

### On the Vault Server

1. Create a Role Mapping a Service Account to a Vault Policy

    ```
    vault write auth/kubernetes/role/myapp \
        bound_service_account_names=myapp \
        bound_service_account_namespaces=default \
        policies=default \
        ttl=1h
    ```

### On the Kubernetes Cluster

1. Run a test pod with a specific service Account

    ```
    kubectl run vault-test --serviceaccount myapp -ti --rm --image ubuntu /bin/bash
    ```

2. View Service Account Token

    ```
    cat /var/run/secrets/kubernetes.io/serviceaccount/token
    ```

3. Install curl for Testing

    ```
    apt update && apt install -y curl
    ```

4. Test Authentication

    - Replace <vault_server_host> with the URL to the Vault host
    - Example: http://vault.default.svc
    ```
    export SA_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    export VAULT_ADDR=<vault_server_host>

    curl \
        --request POST \
        --data '{"jwt": "'${SA_TOKEN}'", "role": "myapp"}' \
        "${VAULT_ADDR}:8200/v1/auth/kubernetes/login"
    ```


## Demo Secrets Access

### On the Vault Server

1. If not already done, enable the KV secrets engine

    ```
    vault secrets enable -version=1 kv 
    ```

2. Write a secret to the KV store

    ```
    vault kv put kv/myapp username=admin password=Password123
    ```

3. Create a policy that gives access to that secret

    ```
    cd /tmp

    cat <<EOF >/tmp/myapp.hcl
    path "kv/myapp" {
    capabilities = ["read"]
    }
    EOF

    vault policy write myapp myapp.hcl
    ```

4. Add myapp policy to the myapp role

    ```
    vault write auth/kubernetes/role/myapp \
        bound_service_account_names=myapp \
        bound_service_account_namespaces=default \
        policies=default,myapp \
        ttl=1h
    ```

### On the Kubernetes Cluster

1. Repeat Steps 1-4 under Test Authentication/On the Kubernetes Cluster

2. Retrieve the Vault token dispayed in previous step

    ```
    export VAULT_TOKEN=<token_from_previous_step>
    ```

4. Test access to the new secret

    ```
    curl \
        --header "X-Vault-Token: $VAULT_TOKEN" \
        "${VAULT_ADDR}:8200/v1/kv/myapp"
    ```

## Accessing Vault on Kubernetes Using Vault Agent and Consul Template

1. Apply ConfigMaps

    ```
    kubectl create configmap example-vault-agent-config --from-file=./configmaps/
    ```

2. Create test pod

    ```
    kubectl apply -f nginx-pod.yaml
    ```

3. Open a shell in the test container

    ```
    kubectl exec -ti vault-agent-example -c nginx /bin/bash
    ```

4. Verify credentials have been written to the pod

    ```
    cat /etc/secrets/myapp
    ```
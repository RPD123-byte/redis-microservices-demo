# Deploy the application on Kubernetes


Prequisites:
* a running Kubernetes cluster

## Install Redis Enterprise Operator

While the Docker deployment is using a simple Redis container, 
for Kubernetes you can use Redis Enterprise that you deploy using an operator. 

You can find more information about Redis Enterprise on Kubernetes in [the documentation](https://docs.redislabs.com/latest/platforms/Kubernetes/).



1. Get the Operator definition

    Clone of download the Redis Enterprise on Kubernetes repository:

    ```
    > git clone https://github.com/RedisLabs/redis-enterprise-k8s-docs.git

    > cd redis-enterprise-k8s-docs.git

    ```

1. Create a new namespace:


    ```bash
    > kubectl create namespace redis-demo
    ```

    Switch context to the newly created namespace:

    ```bash
    > kubectl config set-context --current --namespace=redis-demo
    ```

1. Deploy the operator bundle

   To deploy the default installation with `kubectl`, the following command will deploy a bundle of all the yaml declarations required for the operator:

    ```bash
    > kubectl apply -f bundle.yaml
    ```

1. Verify that `redis-enterprise-operator` deployment is running.

    ```bash
    > kubectl get deployment

    NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
    redis-enterprise-operator          1/1     1            1           2m
    ```

You can find more information about [Redis Enterprise Kubernetes Operator-based Architecture 
](https://docs.redislabs.com/latest/platforms/Kubernetes/Kubernetes-with-operator/) in the documentation.


## Create a Redis Enterprise Cluster

You have now installed the operator, you can create a cluster, that will create, configure and start all necessary pods.

1. Go back in this **project folder** (`redis-microservices-demo`).

    ```
    > cd  redis-microservices-demo/kubernetes
    ```
1. Create the cluster

    The `redis-demo-cluster-crd.yaml` is configured to create a 3 nodes Redis Enterprise Cluster. 

    ```
    > kubectl apply -f redis-demo-cluster-crd.yaml  
    ```

    It will take some time to the operator to start and configure the cluster, you can check the pods status using:

    ```
    > kubectl get pods

    NAME                                               READY   STATUS              RESTARTS   AGE
    redis-enterprise-0                                 2/2     Running             0          4m25s
    redis-enterprise-1                                 2/2     Running             0          2m22s
    redis-enterprise-2                                 0/2     ContainerCreating   0          8s
    redis-enterprise-operator-7997dd5d7b-g5fg4         1/1     Running             0          5m10s
    redis-enterprise-services-rigger-95cbbd7b7-lvxrn   1/1     Running             0          4m25s
    ```

    **Before going to the next step you should wait until the all the pods are `running`.**

    Once all the nodes running you have successfully installed a 3 nodes cluster of Redis Enterprise.


1. Check Redis Cluster Services

    Run the following command:

    ```bash
    kubectl get services

    NAME                  TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                      AGE
    redis-enterprise      ClusterIP      None             <none>          9443/TCP,8001/TCP,8070/TCP   19m
    redis-enterprise-ui   LoadBalancer   10.123.247.213   34.68.204.140   8443:32606/TCP               19m
    ```

    Redis Enterprise comes with a complete Web console to manage and monitor your cluster, you can use the `redis-enterprise-ui` service to access it, using the `EXTERNAL-IP` and port `8443`.

1. Access the Redis Web Console

    As described above you can access the Web Console. you need the administrator user and password. (The user is `kubectl get secret redis-enterprise -o jsonpath="{.data.username}"` defined in the `redis-demo-cluster-crd.yaml` file). These data are stored in a secret associated to the Redis Cluster.

    ```
    > kubectl get secret redis-enterprise -o jsonpath="{.data.username}" | base64 --decode

    admin@demo.com

    > kubectl get secret redis-enterprise -o jsonpath="{.data.password}" | base64 --decode

    Hp0a1PYQ

    ```    

    Do not create the database from the UI, you will use another Kubernetes custom resource in the next step.


Let's now create a Redis database with teh RediSearch and RedisGraph modules enabled.


## Create a Redis Database

The demonstration uses Redis database with 2 modules:
* [RediSearch](http://redisearch.io/)
* [RedisGraph](http://redisgraph.io/)

Using Redis Enterprise you can create a new databaseusing the Web Console, or use the operator to create and configure it. _You will see below how to access the Web Console._

The follow steps will use the operator to create the database named `movie-database`, with the modules, persistence and replication enabled.


1. Deploy the `redis-demo-movie-database-crd.yaml` file, using the following command:

    ```
    > kubectl apply -f redis-demo-movie-database-crd.yaml
    ```

    You can check the status of the database using:

    ```
    > kubectl get services/movie-database  

    NAME             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)     AGE
    movie-database   ClusterIP   10.123.242.191   <none>        18132/TCP   45s
    ```

    The name of the database service is `movie-database`, the redis port is `15291` will vary depending of your installation.
    As  you can see the database is not exposed externally (no `EXTERNAL-IP`).
    This is not an issue since the application will be deployed in the same Kubernetes environment.

    If you go back into the Web Console you will see the newly created database with modules, persistence and replication enabled.


1. Retrieve the connection string

    To connect to the database from the application the application needs:
    * the `hostname`
    * the `port`
    * the `password`


    These information are stored in a secret. You can list the secrets of your namespace using the command `kubectl get secrets`.
    One of the secret is `redb-movie-database` _(`reddb` is the short name for `RedisEnterpriseDatabase` defined in the operator)_.

    You can list the data stored in this secret using the following command:

    ```bash
    kubectl  describe  secrets redb-movie-database
    Name:         redb-movie-database
    Namespace:    redis-demo
    Labels:       <none>
    Annotations:  <none>

    Type:  Opaque

    Data
    ====
    password:      8 bytes
    port:          5 bytes
    service_name:  23 bytes
    ```

    You can see the 3 properties needed to access the database.
    
    If you want to look at the content run the following command:

    ```
    > kubectl get secret redb-movie-database  -o jsonpath={.data.port} | base64 --decode        
    
    18132                                
    ```


### Use the database information in your deployments

Before configuring and deploying the application let's describe how the services will access the database.

Each of the services of the demonstration are configured to receive and set environment variables: `REDIS_HOST` , `REDIS_PORT`, `REDIS_PASSWORD`.

To deploy the application you can simply use the database secret information and apply them to the deployment. For example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
    spec:
      containers:
        - name: app
          image: demo/catalog:1.0.0
          ports:
            - containerPort: 8080
          env:
            - name: REDIS_PORT
              valueFrom:
                secretKeyRef:
                  name: redb-movie-database
                  key: port
            - name: REDIS_HOST
              valueFrom:
                secretKeyRef:
                  name: redb-movie-database
                  key: service_name
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redb-movie-database
                  key: password
          imagePullPolicy: Always
```

You can see the `env` section that get the values from the secret, you can take a look to the Kubernetes documentation: [Using Secrets as environment variables 
](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-environment-variables).


## Configure and deploy the application

The application is made of the following services:

* MySQL
* Caching service
* Database to Stream
* Streams to Redis Hashes
* Streams to Redis Graph
* Comments service
* Web UI
* RedisInsight


## Deploy the application

The `redis-demo-application-deployment.yaml` contains the deployment information for the complete demonstration. Run the following command to deploy the application to your Kubernetes cluster:

```bash
> kubectl apply -f redis-demo-application-deployment.yaml
```

You can check the status of the services using the following command:

```bash
> kubectl get services

NAME                           TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                      AGE
app-caching                    LoadBalancer   10.91.247.105   104.155.182.93   8084:30769/TCP               14m
app-comments                   LoadBalancer   10.91.245.100   34.71.233.138    8086:32376/TCP               14m
app-db-to-streams              LoadBalancer   10.91.254.174   35.223.218.209   8082:30967/TCP               14m
app-frontend                   LoadBalancer   10.91.255.6     34.122.112.62    80:32642/TCP                 14m
app-mysql                      ClusterIP      None            <none>           3306/TCP                     14m
app-redis-insight              LoadBalancer   10.91.251.182   104.154.60.232   8001:31559/TCP               14m
app-sql-rest-api               LoadBalancer   10.91.248.8     35.238.133.156   8081:30046/TCP               14m
app-streams-to-redis-hashes    LoadBalancer   10.91.244.194   35.226.226.187   8085:30081/TCP               14m
app-streams-to-redisgraph      LoadBalancer   10.91.255.210   34.71.45.36      8083:31973/TCP               14m
movie-database                 ClusterIP      10.91.255.235   <none>           11293/TCP                    17m
movie-database-headless        ClusterIP      None            <none>           11293/TCP                    17m
movie-database-load-balancer   LoadBalancer   10.91.245.78    34.122.204.226   11293:30444/TCP              17m
redis-enterprise               ClusterIP      None            <none>           9443/TCP,8001/TCP,8070/TCP   88m
redis-enterprise-ui            LoadBalancer   10.91.243.120   34.72.231.180    8443:30352/TCP               88m
```

The most interesting services for the demonstration are:

* `app-frontend` that exposes the application on port 80, so go to http://[EXTERNAL-IP]/
* `app-redis-insight` that exposes RedisInsight on port 8001, you can go to  http://[EXTERNAL-IP]:8001
* `movie-database-load-balancer` that allows you to connect to the Movie Database outside the Kubernetes cluster, for example from your local environment.


**Connect RedisInsight to your database**

In RedisInsight:

1. Click on "Add Redis Database" button:
1. Click on "Connect to Redis Database / Using Hostname and Port"
1. Enter "`movie-database`" for the Host
1. Enter the port exposed by the `movie-database` service (in the example above it is `11293`)
1. Set Username to `default`
1. Set the password to the value returned by the command `kubectl get secret redb-movie-database  -o jsonpath={.data.password} | base64 --decode`


You can now use RedisInsight to interact with the movie database.



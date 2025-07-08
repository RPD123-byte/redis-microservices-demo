FROM redisdeveloper/rmdb-caching:1.0.0

ENV REDIS_HOST=redis-service
ENV REDIS_PORT=6379
ENV REDIS_PASSWORD=
ENV MYSQL_ROOT_PASSWORD=debezium
ENV MYSQL_USER=mysqluser
ENV MYSQL_PASSWORD=mysqlpw

EXPOSE 8084
ENTRYPOINT ["java","-jar","/app.jar","--spring.profiles.active=prod"]



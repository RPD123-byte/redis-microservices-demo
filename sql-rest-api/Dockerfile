FROM redisdeveloper/rmdb-sql-rest-api:1.0.0

ENV SPRING_DATASOURCE_URL=jdbc:mysql://app-mysql:3306/inventory
ENV SPRING_DATASOURCE_USERNAME=mysqluser
ENV SPRING_DATASOURCE_PASSWORD=mysqlpw

EXPOSE 8081
ENTRYPOINT ["java","-jar","/app.jar","--spring.profiles.active=prod"]



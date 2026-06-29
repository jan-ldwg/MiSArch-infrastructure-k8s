package org.misarch

import io.gatling.javaapi.core.CoreDsl.*
import io.gatling.javaapi.http.HttpDsl.http
import java.time.Duration
import java.util.UUID


val realisticBuyProcess = scenario("realisticBuyProcess")
    .exec { session ->
        session.set("targetUrl", "http://misarch-gateway.misarch.svc.cluster.local:8080/graphql")
    }
    //Get token to authenticate for all future requests
    //this is not part of the realistic user flow since a user would use the login page, not the api
    //a new user is required for each session or else the shopping cart is shared
     .exec(
        http("Get Admin Token")
        .post("http://keycloak.misarch.svc.cluster.local:80/keycloak/realms/master/protocol/openid-connect/token")
        .header("Content-Type", "application/x-www-form-urlencoded")
        .formParam("username", "admin")
        .formParam("password", "admin")
        .formParam("grant_type", "password")
        .formParam("client_id", "admin-cli")
        .check(jsonPath("$.access_token").saveAs("adminToken"))
     )
     .exec { session ->
        session
            .set("username", UUID.randomUUID().toString())
            .set("firstName", UUID.randomUUID().toString())
            .set("lastName", UUID.randomUUID().toString())
            .set("password", UUID.randomUUID().toString())
     }
     .exec(
        http("Create new user")
            .post("http://keycloak.misarch.svc.cluster.local:80/keycloak/admin/realms/Misarch/users")
            .header("Content-Type", "application/json")
            .header("Authorization", "Bearer #{adminToken}")
            .body(StringBody("{ \"username\": \"#{username}\", \"firstName\": \"#{firstName}\", \"lastName\": \"#{lastName}\", \"enabled\": true }"))
    )
    .exitHereIfFailed()
    .exec(
        http("Get User Id")
            .get("http://keycloak.misarch.svc.cluster.local:80/keycloak/admin/realms/Misarch/users?username=#{username}")
            .header("Authorization", "Bearer #{adminToken}")
            .check(jsonPath("$[0].id").saveAs("keycloakUserId"))
    )
    .exitHereIfFailed()
    .exec(
        http("Set password")
            .put("http://keycloak.misarch.svc.cluster.local:80/keycloak/admin/realms/Misarch/users/#{keycloakUserId}/reset-password")
            .header("Authorization", "Bearer #{adminToken}")
            .header("Content-Type", "application/json")
            .body(StringBody("{\"type\": \"password\", \"value\":\"#{password}\", \"temporary\": false}"))

    )
    .exitHereIfFailed()
    .exec(
        http("Get buyer role")
            .get("http://keycloak.misarch.svc.cluster.local:80/keycloak/admin/realms/Misarch/roles/buyer")
            .header("Authorization", "Bearer #{adminToken}")
            .check(jsonPath("$.id").saveAs("buyerId"))
            .check(bodyString().saveAs("buyerRole"))
    )
    .exitHereIfFailed()
    .exec(
        http("Get employee role")
            .get("http://keycloak.misarch.svc.cluster.local:80/keycloak/admin/realms/Misarch/roles/employee")
            .header("Authorization", "Bearer #{adminToken}")
            .check(jsonPath("$.id").saveAs("employeeId"))
            .check(bodyString().saveAs("employeeRole"))
    )
    .exitHereIfFailed()
    .exec(
        http("Assign buyer and employee roles")
            .post("http://keycloak.misarch.svc.cluster.local:80/keycloak/admin/realms/Misarch/users/#{keycloakUserId}/role-mappings/realm")
            .header("Authorization", "Bearer #{adminToken}")
            .header("Content-Type", "application/json")
            .body(StringBody("[#{buyerRole},#{employeeRole}]"))
    )
    .exitHereIfFailed()
    /* 
    .exec(
        http("Publish new user to dapr")
            .post("http://user-dapr:3500/v1.0/publish/pubsub/user/user/create")
            .header("Content-Type", "application/json")
            .body(StringBody("{\"id\":\"#{keycloakUserId}\",\"username\":\"#{username}\",\"firstName\":\"#{firstName}\",\"lastName\":\"#{lastName}\"}"))
    )
    .exitHereIfFailed()
    */
    .pause(Duration.ofMillis(10000), Duration.ofMillis(10000))
    .exec(
        http("Get Access Token")
            .post("http://keycloak.misarch.svc.cluster.local:80/keycloak/realms/Misarch/protocol/openid-connect/token")
            .header("Content-Type", "application/x-www-form-urlencoded")
            .formParam("client_id", "frontend")
            .formParam("grant_type", "password")
            .formParam("username", "#{username}")
            .formParam("password", "#{password}")
            .requestTimeout(Duration.ofSeconds(10))
            .check(jsonPath("$.access_token").saveAs("accessToken"))
    )
    .exitHereIfFailed()
    //Load the webpage
    //This will not load everything dynamically requested by JS
    .exec(
        http("frontpage")
            .get("http://misarch-gateway.misarch.svc.cluster.local:8080")
            .requestTimeout(Duration.ofSeconds(10))
    )
    .exitHereIfFailed()
    .exec { session ->
        session.set(
            "productsQuery",
            "{ \"query\": \"query { products(filter: { isPubliclyVisible: true }, first: 10, orderBy: { direction: ASC, field: ID }, skip: 0) { hasNextPage nodes { id internalName isPubliclyVisible } totalCount } }\" }"
        )
    }
    .exec(
        http("products")
            .post("#{targetUrl}")
            .header("Content-Type", "application/json")
            .header("Authorization", "Bearer #{accessToken}")
            .body(StringBody("#{productsQuery}"))
            .requestTimeout(Duration.ofSeconds(10))
            .check(jsonPath("$.data.products.nodes[0].id").saveAs("productId"))
    )
    .exitHereIfFailed()
    .pause(Duration.ofMillis(4000), Duration.ofMillis(10000))
    .exec { session ->
        val productId = session.getString("productId")
        session.set(
            "productQuery",
            "{ \"query\": \"query { product(id: \\\"$productId\\\") { categories { hasNextPage  totalCount } defaultVariant { id isPubliclyVisible averageRating } id internalName isPubliclyVisible variants { hasNextPage  totalCount } } }\" }"
        )
    }
    .exec(
        http("product").post("#{targetUrl}").header("Content-Type", "application/json").header("Authorization", "Bearer #{accessToken}").body(StringBody("#{productQuery}"))
            .requestTimeout(Duration.ofSeconds(10))
            .check(jsonPath("$.data.product.defaultVariant.id").saveAs("productVariantId"))
    )
    .exitHereIfFailed()
    .pause(Duration.ofMillis(50), Duration.ofMillis(150))
    .exec { session ->
        session.set(
            "userQuery",
            "{ \"query\": \"query getCurrentUser { currentUser { id } }\" }"
        )
    }
    .exec(
        http("users")
            .post("#{targetUrl}")
            .header("Content-Type", "application/json")
            .header("Authorization", "Bearer #{accessToken}")
            .body(StringBody("#{userQuery}"))
            .requestTimeout(Duration.ofSeconds(10))
            .check(jsonPath("$.data.currentUser.id").saveAs("userId"))
    )
    .exitHereIfFailed()
    .pause(Duration.ofMillis(50), Duration.ofMillis(150))
    .exec { session ->
        val userId = session.getString("userId")
        session.set(
            "addressMutation",
            "{ \"query\": \"mutation { createUserAddress(input:{ city: \\\"Stuttgart\\\", companyName: \\\"University of Stuttgart\\\", country: \\\"Germany\\\", postalCode: \\\"70569\\\", street1: \\\"Universitaetsstrasse\\\", street2: \\\"38\\\", userId: \\\"$userId\\\" }) { id } }\" }"
        )
    }
    .exec(
        http("Add address to user")
            .post("#{targetUrl}")
            .header("Content-Type", "application/json")
            .header("Authorization", "Bearer #{accessToken}")
            .body(StringBody("#{addressMutation}"))
            .requestTimeout(Duration.ofSeconds(10))
    )
    .exitHereIfFailed()
    .pause(Duration.ofMillis(50), Duration.ofMillis(150))
    .exec { session ->
        session.set(
            "addressQuery",
            "{ \"query\": \"query getActiveAddressesOfCurrentUser(\$orderBy: UserAddressOrderInput = {}) { currentUser { addresses(orderBy: \$orderBy, filter: { isArchived: false }) { totalCount nodes { id city companyName country name { firstName lastName } postalCode street1 street2 } } } }\" }"
        )
    }
    .exec(
        http("address").post("#{targetUrl}").header("Content-Type", "application/json").header("Authorization", "Bearer #{accessToken}").body(StringBody("#{addressQuery}"))
            .requestTimeout(Duration.ofSeconds(10))
            .check(jsonPath("$.data.currentUser.addresses.nodes[0].id").saveAs("addressId"))
    )
    .exitHereIfFailed()
    .pause(Duration.ofMillis(50), Duration.ofMillis(150))
    .exec { session ->
        val userId = session.getString("userId")
        val productVariantId = session.getString("productVariantId")
        session.set(
            "createShoppingcartItemMutation",
            "{ \"query\": \"mutation { createShoppingcartItem( input: { id: \\\"$userId\\\" shoppingCartItem: { count: 1 productVariantId: \\\"$productVariantId\\\" } } ) { id } }\" }"
        )
    }
    .exec(
        http("createShoppingcartItemMutation").post("#{targetUrl}").header("Content-Type", "application/json").header("Authorization", "Bearer #{accessToken}").body(StringBody("#{createShoppingcartItemMutation}"))
            .requestTimeout(Duration.ofSeconds(10))
            .check(jsonPath("$.data.createShoppingcartItem.id").saveAs("createShoppingcartItemId"))
    )
    .exitHereIfFailed()
    .pause(Duration.ofMillis(4000), Duration.ofMillis(7000))
    .exec { session ->
        session.set(
            "shipmentMethodsQuery",
            "{ \"query\": \"query getShipmentMethods(\$isArchived: Boolean = false) { shipmentMethods(filter: { isArchived: \$isArchived }) { totalCount nodes { id baseFees description feesPerItem feesPerKg name } } } \" }",
        )
    }
    .exec(
        http("shipmentMethodsQuery").post("#{targetUrl}").header("Content-Type", "application/json").header("Authorization", "Bearer #{accessToken}").body(StringBody("#{shipmentMethodsQuery}"))
            .requestTimeout(Duration.ofSeconds(10))
            .check(jsonPath("$.data.shipmentMethods.nodes[0].id").saveAs("shipmentMethodId"))
    )
    .exitHereIfFailed()
    .pause(Duration.ofMillis(0), Duration.ofMillis(0))
    .exec { session ->
        session.set(
            "paymentInformationsQuery",
            "{ \"query\": \"query getPaymentInformationOfCurrentUser(\$paymentMethod: PaymentMethod) { currentUser { id paymentInformations(filter:{ paymentMethod: \$paymentMethod }) { totalCount nodes { id paymentMethod publicMethodDetails } } } }\" }",
        )
    }
    .exec(
        http("paymentInformationsQuery").post("#{targetUrl}").header("Content-Type", "application/json").header("Authorization", "Bearer #{accessToken}").body(StringBody("#{paymentInformationsQuery}"))
            .requestTimeout(Duration.ofSeconds(10))
            .check(jsonPath("$.data.currentUser.paymentInformations.nodes[0].id").saveAs("paymentInformationId"))
    )
    .exitHereIfFailed()
    .pause(Duration.ofMillis(4000), Duration.ofMillis(7000))
    .exec { session ->
        val userId = session.getString("userId")
        val addressId = session.getString("addressId")
        val createShoppingcartItemId = session.getString("createShoppingcartItemId")
        val shipmentMethodId = session.getString("shipmentMethodId")
        val paymentInformationId = session.getString("paymentInformationId")
        session.set(
            "createOrderMutation",
            "{ \"query\": \"mutation { createOrder( input: { userId: \\\"$userId\\\" orderItemInputs: { shoppingCartItemId: \\\"$createShoppingcartItemId\\\" couponIds: [] shipmentMethodId: \\\"$shipmentMethodId\\\" } vatNumber: \\\"AB1234\\\" invoiceAddressId: \\\"$addressId\\\" shipmentAddressId: \\\"$addressId\\\" paymentInformationId: \\\"$paymentInformationId\\\" } ) { id paymentInformationId placedAt } }\" }"
        )
    }
    .exec(
        http("createOrderMutation").post("#{targetUrl}").header("Content-Type", "application/json").header("Authorization", "Bearer #{accessToken}").body(StringBody("#{createOrderMutation}"))
            .requestTimeout(Duration.ofSeconds(10))
            .check(jsonPath("$.data.createOrder.id").saveAs("createOrderId"))
    )
    .exitHereIfFailed()
    .pause(Duration.ofMillis(8000), Duration.ofMillis(12000))
    .exec { session ->
        val createOrderId = session.getString("createOrderId")
        session.set(
            "placeOrderMutation",
            "{ \"query\": \"mutation { placeOrder(input: { id: \\\"$createOrderId\\\", paymentAuthorization: { cvc: 123 } }) { id } }\" }"
        )
    }
    .exec(
        http("placeOrderMutation").post("#{targetUrl}").header("Content-Type", "application/json").header("Authorization", "Bearer #{accessToken}").body(StringBody("#{placeOrderMutation}"))
            .requestTimeout(Duration.ofSeconds(10))
    )
    .exitHereIfFailed()
    .pause(Duration.ofMillis(0), Duration.ofMillis(0))
rekor:
  namespace:
    name: rekor-system
    create: false
  server:
    ingress:
      className: ""
      annotations:
        route.openshift.io/termination: "edge"
      hosts:
        - host: rekor.apps.$BASE_DOMAIN
          path: /


fulcio:
  namespace:
    name: fulcio-system
    create: false
  createcerts:
    enabled: false
  server:
    secret: $FULCIO_SERVER_SECRET_NAME
    ingress:
      http:
        annotations:
          route.openshift.io/termination: "edge"
        className: ""
        hosts:
          - host: fulcio.apps.$BASE_DOMAIN
            path: /
  config:
    contents:
      OIDCIssuers:
        ? https://keycloak-keycloak-system.apps.$BASE_DOMAIN/auth/realms/sigstore
        : IssuerURL: https://keycloak-keycloak-system.apps.$BASE_DOMAIN/auth/realms/sigstore
          ClientID: sigstore
          Type: email

tuf:
  namespace:
    name: tuf-system
    create: false
  secrets:
    fulcio:
      name: $FULCIO_SERVER_SECRET_NAME
  enabled: true
  ingress:
    className: ""
    annotations:
      route.openshift.io/termination: "edge"
    http:
      hosts:
        - host: tuf.apps.$BASE_DOMAIN
          path: /

ctlog:
  namespace:
    name: ctlog-system
    create: false
  createctconfig:
    backoffLimit: 30

trillian:
  namespace:
    name: trillian-system
    create: false

tsa:
  enabled: false

copySecretJob:
  enabled: true
  backoffLimit: 1000
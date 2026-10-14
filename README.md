I'll give you a Java-based SAP BusinessObjects user-management client for your LOCAL, UAT, and PROD environments.

Since your PowerShell version already works in LOCAL and UAT, the Java version should use the same supported SAP BO REST API rather than trying to bypass PROD permissions. We'll separate login, read-only user listing, and user deletion, and keep production deletion protected.

The initial version below tests authentication and lists users. Once PROD login is confirmed, deletion can be added with explicit confirmation and verification.

SAP's documentation confirms that the BI REST API can be called from any language supporting HTTP requests, including Java. Login uses `POST /logon/long`, and subsequent requests pass the token in the `X-SAP-LogonToken` header.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://help.sap.com\&sz=32)

SAP Help Portal

+1



## 1. Java code — SAP BO PROD login and user listing

This version uses Java 11 or later and requires no third-party libraries.

Save as `SapBoUserManager.java`.

```

import java.io.Console;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Scanner;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;
import java.io.StringReader;

public class SapBoUserManager {

    private static final String PROD_URL =
        "https://gfsbi4.capgemini.com/biprws";

    private final HttpClient client = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(20))
        .build();

    private String baseUrl;
    private String token;

    private static String xmlEscape(String value) {
        return value.replace("&", "&amp;")
                    .replace("<", "&lt;")
                    .replace(">", "&gt;")
                    .replace("\"", "&quot;")
                    .replace("'", "&apos;");
    }

    private Document parseXml(String xml) throws Exception {
        DocumentBuilderFactory factory =
            DocumentBuilderFactory.newInstance();

        factory.setFeature(
            "http://apache.org/xml/features/disallow-doctype-decl",
            true
        );
        factory.setFeature(
            "http://xml.org/sax/features/external-general-entities",
            false
        );
        factory.setFeature(
            "http://xml.org/sax/features/external-parameter-entities",
            false
        );
        factory.setXIncludeAware(false);
        factory.setExpandEntityReferences(false);
        factory.setNamespaceAware(true);

        return factory.newDocumentBuilder().parse(
            new InputSource(new StringReader(xml))
        );
    }

    private String postXml(String path, String body)
            throws Exception {

        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create(baseUrl + path))
            .timeout(Duration.ofSeconds(60))
            .header("Content-Type", "application/xml")
            .header("Accept", "application/xml")
            .POST(HttpRequest.BodyPublishers.ofString(body))
            .build();

        HttpResponse<String> response = client.send(
            request, HttpResponse.BodyHandlers.ofString()
        );

        if (response.statusCode() < 200 ||
            response.statusCode() >= 300) {
            throw new IllegalStateException(
                "HTTP " + response.statusCode()
                + " from " + path
                + ". Response: "
                + response.body().substring(
                    0, Math.min(500, response.body().length())
                )
            );
        }

        return response.body();
    }

    private void login(String username, String password,
                       String authType) throws Exception {

        String body =
            "<attrs xmlns=\"http://www.sap.com/rws/bip\">" +
            "<attr name=\"userName\" type=\"string\">" +
            xmlEscape(username) + "</attr>" +
            "<attr name=\"password\" type=\"string\">" +
            xmlEscape(password) + "</attr>" +
            "<attr name=\"auth\" type=\"string\">" +
            xmlEscape(authType) + "</attr>" +
            "</attrs>";

        token = null;
        String response = postXml("/logon/long", body);
        Document doc = parseXml(response);

        NodeList attrs = doc.getElementsByTagNameNS(
            "http://www.sap.com/rws/bip", "attr"
        );

        for (int i = 0; i < attrs.getLength(); i++) {
            Element attr = (Element) attrs.item(i);
            String name = attr.getAttribute("name");

            if ("logonToken".equalsIgnoreCase(name)) {
                token = attr.getTextContent().trim();
                break;
            }
        }

        if (token == null || token.isEmpty()) {
            throw new IllegalStateException(
                "Login response did not contain a logon token."
            );
        }

        System.out.println("Login successful.");
    }

    private String get(String path) throws Exception {
        HttpRequest request = HttpRequest.newBuilder()
            .uri(URI.create(baseUrl + path))
            .timeout(Duration.ofSeconds(60))
            .header("Accept", "application/atom+xml")
            .header("X-SAP-LogonToken", "\"" + token + "\"")
            .GET()
            .build();

        HttpResponse<String> response = client.send(
            request, HttpResponse.BodyHandlers.ofString()
        );

        if (response.statusCode() < 200 ||
            response.statusCode() >= 300) {
            throw new IllegalStateException(
                "HTTP " + response.statusCode()
                + " while listing users. Response: "
                + response.body().substring(
                    0, Math.min(500, response.body().length())
                )
            );
        }

        return response.body();
    }

    private void listUsers() throws Exception {
        int page = 1;
        int pageSize = 100;

        while (true) {
            String path = "/v1/users?page=" + page
                        + "&pagesize=" + pageSize;

            Document doc = parseXml(get(path));
            NodeList entries = doc.getElementsByTagNameNS(
                "http://www.w3.org/2005/Atom", "entry"
            );

            if (entries.getLength() == 0) {
                if (page == 1) {
                    System.out.println("No users returned.");
                }
                break;
            }

            for (int i = 0; i < entries.getLength(); i++) {
                Element entry = (Element) entries.item(i);

                String name = childText(entry, "name");
                String id = childText(entry, "id");

                System.out.printf("User: %s | ID: %s%n",
                    name, id);
            }

            if (entries.getLength() < pageSize) {
                break;
            }

            page++;
        }
    }

    private String childText(Element parent, String localName) {
        NodeList nodes = parent.getElementsByTagNameNS("*", localName);
        if (nodes.getLength() == 0) {
            return "";
        }
        return nodes.item(0).getTextContent().trim();
    }

    public static void main(String[] args) {
        SapBoUserManager app = new SapBoUserManager();

        Console console = System.console();
        Scanner scanner = new Scanner(System.in);

        try {
            System.out.println("SAP BUSINESSOBJECTS USER MANAGER");
            System.out.println("1. LOCAL");
            System.out.println("2. UAT");
            System.out.println("3. PROD");
            System.out.print("Select environment: ");

            String choice = scanner.nextLine().trim();

            switch (choice) {
                case "1":
                    app.baseUrl = "http://localhost:8080/biprws";
                    break;
                case "2":
                    app.baseUrl =
                        "https://gfsbi4newuat.capgemini.com/biprws";
                    break;
                case "3":
                    app.baseUrl = PROD_URL;
                    System.out.println(
                        "PROD selected: read-only login/list test."
                    );
                    break;
                default:
                    throw new IllegalArgumentException(
                        "Invalid environment selection."
                    );
            }

            System.out.print("Authentication (secEnterprise/secWinAD): ");
            String auth = scanner.nextLine().trim();

            if (!auth.equals("secEnterprise") &&
                !auth.equals("secWinAD")) {
                throw new IllegalArgumentException(
                    "Unsupported authentication choice."
                );
            }

            System.out.print("Username: ");
            String username = scanner.nextLine().trim();

            String password;
            if (console != null) {
                char[] chars = console.readPassword("Password: ");
                password = new String(chars);
                java.util.Arrays.fill(chars, '\0');
            } else {
                System.out.println(
                    "No console available; use a terminal for hidden password input."
                );
                throw new IllegalStateException(
                    "Run this program in a terminal, not an IDE output pane."
                );
            }

            app.login(username, password, auth);
            app.listUsers();

        } catch (Exception e) {
            System.err.println("ERROR: " + e.getMessage());
            System.err.println(
                "No users were deleted by this read-only version."
            );
        }
    }
}

```

## 2. Compile and run

Open a terminal in the folder containing the file:

```
javac SapBoUserManager.java
java SapBoUserManager
```

Select `3` to test PROD. This version only attempts login and lists users; it does not delete or modify anything.

## 3. How to interpret the result

- Login successful, users listed: The Java client can authenticate and read users in that environment.
- HTTP 401 during login: Check the PROD authentication method, username format, and server-side authentication configuration with your BO/Basis team.
- Login succeeds but listing returns 401: Check token handling, session behavior, and whether the request is reaching the same web tier.
- 403 or an authorization error: The authenticated account may lack permission for the requested operation.

One important detail: if your Java code encounters a TLS certificate error, don't disable certificate validation. Have the correct corporate certificate chain installed.

Next step: Run this read-only version against PROD and share the HTTP status and sanitized error message. Do not share your password or logon token. Once the result is clear, we can add controlled deletion with a target preview, protected-account checks, a confirmation prompt, and verification.

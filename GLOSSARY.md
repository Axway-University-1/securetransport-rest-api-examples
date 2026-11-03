# Glossary

The terms and acronyms used throughout this project. [Back to the README](README.md).

The following table shows a list of terms and acronyms used throughout this project.

| Definition | Description |
| ---------- | ----------- |
| Admin API, EndUser API | The administrator's API (port 444, or 8444 on a non root install) and the smaller user level API (port 443, or 8443) |
| Advanced Routing | The SecureTransport feature that moves and transforms files by routes |
| Account | A user, service or template account; the owner of a home folder, sites and subscriptions |
| AS2, PeSIT, SFTP | File transfer protocols the server speaks (as listener and as client through a site) |
| Business unit | A group of accounts with its own settings and, optionally, a network zone |
| coreId | The id that ties the transfers of one file's journey through the server together |
| CSRF token | A header, returned by the login, that a session must send back on writes; see the gotchas |
| DMZ, zone, edge | A network zone and its edge server that sits between the outside and the core |
| EL | The Expression Language: `${...}` in route conditions, filters, rename patterns and login rules |
| ICAP | A protocol for passing files to a virus scanner |
| Route | A template, a simple or a composite route of Advanced Routing, run by a subscription |
| Site (transfer site) | A remote partner the server connects to, to pull or push files |
| Subscription | What links an account's folder to an application: a route or a trigger |
| ST | SecureTransport |
| MFT, TLS, JSON | Managed File Transfer, Transport Layer Security, JavaScript Object Notation |

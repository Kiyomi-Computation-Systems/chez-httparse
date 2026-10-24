# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| The latest release (see [CHANGELOG.md](CHANGELOG.md)) | ✅ |
| Earlier releases | ❌ |

## Reporting a vulnerability

Please report suspected vulnerabilities privately via GitHub:
**Security → Report a vulnerability** on this repository. Do not open a
public issue.

You can expect an acknowledgement within 7 days.

This parser reads bytes off the network, so these reports are especially
welcome:

- request smuggling or desync: a message whose framing it reads differently
  from llhttp, or from a proxy in front of it;
- input it accepts that it should refuse;
- input that makes it allocate in proportion to its size, or loop.

Please include your platform, Chez version, the parser's mode (request or
response, lenient flags) and the bytes that show it, with how they were
split across feeds.

A report about the generator's runtime (byte-machine) is welcome here too.

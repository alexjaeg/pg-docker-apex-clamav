import sys

file_path = "src/squidclamav.c"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target1 = """    if ((sockd = dconnect ()) < 0) {
        debugs(0, "ERROR Can't connect to Clamd daemon.\\n");
        return CI_MOD_ERROR;
    }"""

replacement1 = """    if ((sockd = dconnect ()) < 0) {
        debugs(0, "ERROR Can't connect to Clamd daemon. Enforcing FAIL-CLOSED.\\n");
        data->virus = 1;
        data->malware = ci_buffer_alloc(38);
        strcpy(data->malware, "ClamAV-Scanner-Offline FOUND");
        if (!ci_req_sent_data(req)) {
            generate_response_page(req, data);
        }
        return CI_MOD_DONE;
    }"""

target2 = """    if (write(sockd, "zINSTREAM", 10) <= 0) {
        debugs(0, "ERROR Can't write to Clamd socket.\\n");
        close(sockd);
        return CI_MOD_ERROR;
    }"""

replacement2 = """    if (write(sockd, "zINSTREAM", 10) <= 0) {
        debugs(0, "ERROR Can't write to Clamd socket. Enforcing FAIL-CLOSED.\\n");
        close(sockd);
        data->virus = 1;
        data->malware = ci_buffer_alloc(38);
        strcpy(data->malware, "ClamAV-Scanner-Offline FOUND");
        if (!ci_req_sent_data(req)) {
            generate_response_page(req, data);
        }
        return CI_MOD_DONE;
    }"""

if target1 not in content or target2 not in content:
    print(f"Error: Targets not found in {file_path}")
    sys.exit(1)

content = content.replace(target1, replacement1, 1)
content = content.replace(target2, replacement2, 1)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print(f"Successfully applied Fail-Closed patch to {file_path}")

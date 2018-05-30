-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# openssh_portable Grammar Module

## Variables
* `printf_messages`
--]]

local l = require "lpeg"
l.locale(l)
local ip = require "lpeg.ip_address"

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local ipv46 = ip.v4_field + ip.v6_field

printf_messages = {
    -- openssh-portable/auth.c
    -- {"%s %s%s%s for %s%.100s from %.200s port %d ssh2%s%s", "authmsg", "method", "submethod != NULL ? "/" : """, "submethod == NULL ? "" : submethod", "authctxt->valid ? "" : "invalid user "", "authctxt->user", "ssh_remote_ipaddr(ssh)", "ssh_remote_port(ssh)", "extra != NULL ? ": " : """, "extra != NULL ? extra : """},
    {"%s %s%s%s for %s%.100s from %.200s port %d ssh2%s%s",
        "authmsg",
        l.Cg((l.P(1)-l.S"/ ")^1, "method"),
        l.P"/"^-1,
        (l.Cg((l.P(1)-l.S" ")^1, "submethod"))^-1,
        l.P"invalid user "^-1,
        "user",
        l.Cg(ipv46, "ssh_remote_ipaddr"),
        "ssh_remote_port",
        l.P":"^-1,
        "extra"
    },

    -- openssh-portable/nchan.c
    {"channel %d: chan_shutdown_write: close() failed for fd %d: %.100s", "self", "wfd", "strerror"},
    {"channel %d: chan_shutdown_read: close() failed for fd %d: %.100s", "self", "rfd", "strerror"},

    -- openssh-portable/openbsd-compat/port-aix.c
    {"Can't retrieve attribute SYSTEM for %s: %.100s", "user", "strerror"},
    {"Can't retrieve attribute auth1 for %s: %.100s", "user", "strerror"},
    {"Account %s has unsupported auth1 value '%s'", "user", "p"},
    {"Password can't be changed for user %s: %.100s", "name", "msg"},
    {"Login restricted for %s: %.100s", "pw_name", "msg"},

    -- openssh-portable/openbsd-compat/port-linux.c
    {"%s: getcon failed with %s", "__func__", "strerror"},

    -- openssh-portable/mux.c
    {"%s: invalid forwarding type %u", "__func__", "ftype"},
    {"%s: streamlocal and dynamic forwards are mutually exclusive", "__func__"},
    {"%s: invalid listen port %u", "__func__", "listen_port"},
    {"%s: invalid connect port %u", "__func__", "connect_port"},
    {"%s: missing connect host", "__func__"},
    {"slave-requested %s failed", "fwd_desc"},

    -- openssh-portable/sshconnect.c
    {"Server version \"%.100s\" uses unsafe RSA signature scheme; disabling use of RSA keys", "remote_version"},
    {"%s host key for IP address '%.128s' not in list of known hosts.", "type", "ip"},
    {"Failed to add the %s host key for IP address '%.128s' to the list of known hosts (%.500s).", "type", "ip", "user_hostfiles"},
    {"Warning: Permanently added the %s host key for IP address '%.128s' to the list of known hosts.", "type", "ip"},
    {"Host key fingerprint is %s\n%s", "fp", "ra"},
    {"Failed to add the host to the list of known hosts (%.500s).", "user_hostfiles"},
    {"Warning: Permanently added '%.200s' (%s) to the list of known hosts.", "hostp", "type"},
    {"%s", "msg"},
    {"WARNING: %s key found for host %s\nin %s:%lu\n%s key fingerprint %s.", "key_type", "host", "file", "line", "key_type", "fp"},

    -- openssh-portable/ssh-keygen.c
    {"%s:%lu: ignoring host name with wildcard: %.64s", "path", "linenum", "hosts"},
    {"%s:%lu: invalid line", "path", "linenum"},
    {"Host %s not found in %s", "name", "identity_file"},
    {"WARNING: %s contains unhashed entries", "old"},
    {"Signed %s key %s: id \"%s\" serial %llu%s%s valid %s", "sshkey_cert_type", "out", "key_id", "serial", l.P" for " + l.P"", "cert_principals", "valid"},

    -- openssh-portable/auth2.c
    {"Authentication methods list \"%s\" contains disabled method, skipping", "auth_methods"},

    -- openssh-portable/auth-options.c
    {"Authentication tried for %.100s with correct key but not from a permitted host (host=%.200s, ip=%.200s).", "pw_name", "remote_host", "remote_ip"},
    {"Bad options in %.100s file, line %lu: %.50s", "file", "linenum", "opts"},
    {"Authentication tried for %.100s with valid certificate but not from a permitted host (ip=%.200s).", "pw_name", "remote_ip"},
    {"Certificate extension \"%s\" is not supported", "name"},

    -- openssh-portable/gss-serv-krb5.c
    {"krb5_parse_name(): %.100s", "errmsg"},
    {"Authorized to %s, krb5 principal %s (krb5_kuserok)", "name", "value"},
    {"krb5_cc_new_unique(): %.100s", "errmsg"},
    {"krb5_cc_gen_new(): %.100s", "krb5_get_err_text"},
    {"ssh_krb5_cc_gen(): %.100s", "errmsg"},
    {"krb5_cc_initialize(): %.100s", "errmsg"},

    -- openssh-portable/dh.c
    {"WARNING: could not open %s (%s), using fixed modulus", "_PATH_DH_MODULI", "strerror"},
    {"WARNING: no suitable primes in %s", "_PATH_DH_MODULI"},
    {"WARNING: line %d disappeared in %s, giving up", "which", "_PATH_DH_MODULI"},
    {"invalid public DH value (%d/%d)", "bits_set", "BN_num_bits"},

    -- openssh-portable/session.c
    {"User %.100s not allowed because %s exists", "pw_name", "nl"},
    {"subsystem request for %.100s by user %s failed, subsystem not found", "subsys", "pw_name"},
    {"%s: no session %d req %.100s", "__func__", "self", "rtype"},

    -- openssh-portable/sftp-client.c
    {"%s: not a regular file\n", "new_src"},
    {"%s: lstat failed: %s", "filename", "strerror"},

    -- openssh-portable/sshd.c
    {"RESTART FAILED: av[0]='%.100s', error: %.100s.", "saved_argv", "strerror"},
    {"Could not write ident string to %s port %d", "ssh_remote_ipaddr", "ssh_remote_port"},
    {"Did not receive identification string from %s port %d", "ssh_remote_ipaddr", "ssh_remote_port"},
    {"Bad protocol version identification '%.100s' from %s port %d", "client_version_string", "ssh_remote_ipaddr", "ssh_remote_port"},
    {"probed from %s port %d with %s. Don't panic.", "ssh_remote_ipaddr", "ssh_remote_port", "client_version_string"},
    {"scanned from %s port %d with %s. Don't panic.", "ssh_remote_ipaddr", "ssh_remote_port", "client_version_string"},
    {"Client version \"%.100s\" uses unsafe RSA signature scheme; disabling use of RSA keys", "remote_version"},
    {"Protocol major versions differ for %s port %d: %.200s vs. %.200s", "ssh_remote_ipaddr", "ssh_remote_port", "server_version_string", "client_version_string"},
    {"Server listening on %s port %s%s%s.", "ntop", l.Cg(l.digit^1, "strport"), l.P" rdomain " + l.P"", "rdomain"},
    {"Received signal %d; terminating.", "received_sigterm"},

    -- openssh-portable/auth.c
    {"User %.100s not allowed because account is locked", "pw_name"},
    {"User %.100s not allowed because shell %.100s does not exist", "pw_name", "shell"},
    {"User %.100s not allowed because shell %.100s is not executable", "pw_name", "shell"},
    {"User %.100s from %.100s not allowed because listed in DenyUsers", "pw_name", "hostname"},
    {"User %.100s from %.100s not allowed because not listed in AllowUsers", "pw_name", "hostname"},
    {"User %.100s from %.100s not allowed because not in any group", "pw_name", "hostname"},
    {"User %.100s from %.100s not allowed because a group is listed in DenyGroups", "pw_name", "hostname"},
    {"User %.100s from %.100s not allowed because none of user's groups are listed in AllowGroups", "pw_name", "hostname"},
    {"ROOT LOGIN REFUSED FROM %.200s port %d", "ssh_remote_ipaddr", "ssh_remote_port"},
    {"Authentication refused for %.100s: bad owner or modes for %.200s", "pw_name", "user_hostfile"},
    {"User %s %s %s is not a regular file", "pw_name", "file_type", "file"},
    {"Authentication refused: %s", "line"},
    {"Login name %.100s does not match stored username %.100s", "user", "pw_name"},
    {"Invalid user %.100s from %.100s port %d", "user", "ssh_remote_ipaddr", "ssh_remote_port"},
    {"Nasty PTR record \"%s\" is set up for %s, ignoring", "name", "ntop"},
    {"reverse mapping checking getaddrinfo for %.700s [%s] failed.", "name", "ntop"},
    {"Address %.100s maps to %.600s, but this does not map back to the address.", "ntop", "name"},

    -- openssh-portable/dispatch.c
    {"dispatch_protocol_error: type %d seq %u", "type", "seq"},
    {"dispatch_protocol_ignore: type %d seq %u", "type", "seq"},

    -- openssh-portable/clientloop.c
    {"DISPLAY \"%s\" invalid; disabling X11 forwarding", "display"},
    {"Timeout, server %s not responding.", "host"},

    -- openssh-portable/auth2-pubkey.c
    {"%s: unsupported public key algorithm: %s", "__func__", "pkalg"},
    {"refusing previously-used %s key", "sshkey_type"},
    {"%s: key type %s not in PubkeyAcceptedKeyTypes", "__func__", "sshkey_ssh_name"},

    -- openssh-portable/monitor.c
    {"wrong user name passed to monitor: expected %s != %.100s", "userstyle", "cp"},

    -- openssh-portable/auth-shadow.c
    {"Account %.100s has expired", "sp_namp"},
    {"User %.100s password has expired (root forced)", "user"},
    {"User %.100s password has expired (password aged)", "user"},

    -- openssh-portable/auth-rhosts.c
    {"User %s hosts file %s is not a regular file", "server_user", "filename"},
    {"Rhosts authentication refused for %.100s: no home directory %.200s", "pw_name", "pw_dir"},
    {"Rhosts authentication refused for %.100s: bad ownership or modes for home directory.", "pw_name"},
    {"Rhosts authentication refused for %.100s: bad modes for %.200s", "pw_name", "buf"},

    -- openssh-portable/ssh.c
    {"No user exists for uid %lu", "original_real_uid"},
    {"%s, %s", "SSH_RELEASE", "version"},
    {"Allocated port %u for remote forward to %s:%d", "allocated_port", "connect_host", "connect_port"},
    {"Warning: remote port forwarding failed for listen path %s", "listen_path"},
    {"Warning: remote port forwarding failed for listen port %d", "listen_port"},

    -- openssh-portable/moduli.c
    {"Limited memory: %u MB; limit %lu MB", "largememory", "LARGE_MAXIMUM"},
    {"Increased memory: %u MB; need %u bytes", "largememory", "bytes"},
    {"Decreased memory: %u MB; want %u bytes", "largememory", "bytes"},
    {"%.24s Sieve next %u plus %u-bit", "ctime", "largenumbers", "power"},
    {"%.24s Sieved with %u small primes in %lld seconds", "ctime", "largetries", "duration"},
    {"%.24s Found %u candidates", "ctime", "r"},
    {"mkstemp(%s): %s", "tmp", "strerror"},
    {"write_checkpoint: fdopen: %s", "strerror"},
    {"failed to write to checkpoint file '%s': %s", "cpfile", "strerror"},
    {"Failed to load checkpoint from '%s'", "cpfile"},
    {"Loaded checkpoint from '%s' line %lu", "cpfile", "lineno"},
    {"%.24s processed %lu in %s", "ctime", "processed", "fmt_time"},
    {"%.24s processed %lu of %lu (%lu%%) in %s, ETA %s", "ctime", "processed", "num_to_process", "percent", "fmt_time", "eta_str"},
    {"%.24s Found %u safe primes of %u candidates in %ld seconds", "ctime", "count_out", "count_possible", "duration"},

    -- openssh-portable/channels.c
    {"%s: %d: bad id", "__func__", "id"},
    {"%s: %d: bad id: channel free", "__func__", "id"},
    {"Non-public channel %d, type %d.", "id", "type"},
    {"channel_send_open: %d: bad id", "id"},
    {"%s: %d: unknown channel id", "__func__", "id"},
    {"channel %d: rcvd big packet %zu, maxpack %u", "self", "win_len", "local_maxpacket"},
    {"channel %d: rcvd too much data %zu, win %u", "self", "win_len", "local_window"},
    {"channel %d: ext data for non open", "self"},
    {"channel %d: bad ext data", "self"},
    {"channel %d: rcvd too much extended_data %zu, win %u", "self", "data_len", "local_window"},
    {"channel %d: open failed: %s%s%s", "self", l.Cg((l.P(1) - ":")^0, "reason2txt"), l.P": " + l.P"", "msg"},
    {"Received window adjust for non-open channel %d.", "id"},
    {"%s: %d: unknown", "__func__", "id"},
    {"Received request to connect to host %.100s port %d, but the request was denied.", "host", "port"},
    {"Received request to connect to path %.100s, but the request was denied.", "path"},

    -- openssh-portable/serverloop.c
    {"Timeout, client not responding from %s", "remote_id"},
    {"Exiting on signal %d", "received_sigterm"},
    {"refused local port forward: originator %s port %d, target %s port %d", "originator", "originator_port", "target", "target_port"},
    {"refused streamlocal port forward: originator %s port %d, target %s", "originator", "originator_port", "target"},

    -- openssh-portable/packet.c
    {"Finished discarding for %.200s port %d", "ssh_remote_ipaddr", "ssh_remote_port"},
    {"Bad packet length %u.", "packlen"},
    {"padding error: need %d block %d mod %d", "need", "block_size", "need % block_size"},
    {"Disconnecting %s: %.100s", "remote_id", "buf"},
    {"packet_set_maxsize: called twice: old %d new %d", "max_packet_size", "s"},
    {"packet_set_maxsize: bad size %d", "s"},

    -- openssh-portable/compat.c
    {"ignoring bad proto spec: '%s'.", "p"},

    -- openssh-portable/ttymodes.c
    {"tcgetattr: %.100s", "strerror"},
    {"parse_tty_modes: unknown opcode %d", "opcode"},
    {"parse_tty_modes: n_bytes_ptr != n_bytes: %d %d", "n_bytes_ptr", "n_bytes"},
    {"Setting tty modes failed: %.100s", "strerror"},

    -- openssh-portable/sftp-server.c
    {"%s%sclose \"%s\" bytes read %llu written %llu", "emsg", l.P" " + l.P"", "handle_to_name", "handle_bytes_read", "handle_bytes_write"},
    {"%s%sclosedir \"%s\"", "emsg", l.P" " + l.P"", "handle_to_name"},
    {"sent status %s", "status_to_message"},
    {"open \"%s\" flags %s mode 0%o", "name", "string_from_portable", "mode"},
    {"set \"%s\" size %llu", "name", "size"},
    {"set \"%s\" mode %04o", "name", "perm"},
    {"set \"%s\" modtime %s", "name", "buf"},
    {"set \"%s\" owner %lu group %lu", "name", "uid", "gid"},
    {"opendir \"%s\"", "path"},
    {"remove name \"%s\"", "name"},
    {"mkdir name \"%s\" mode 0%o", "name", "mode"},
    {"rmdir name \"%s\"", "name"},
    {"rename old \"%s\" new \"%s\"", "oldpath", "newpath"},
    {"symlink old \"%s\" new \"%s\"", "oldpath", "newpath"},
    {"posix-rename old \"%s\" new \"%s\"", "oldpath", "newpath"},
    {"statvfs \"%s\"", "path"},
    {"hardlink old \"%s\" new \"%s\"", "oldpath", "newpath"},
    {"session closed for local user %s from [%s]", "pw_name", "client_addr"},
    {"session opened for local user %s from [%s]", "pw_name", "client_addr"},

    -- openssh-portable/loginrec.c
    {"Writing login record failed for %s", "username"},
    {"%s: tty not found", "__func__"},
    {"%s: lseek: %s", "__func__", "strerror"},
    {"%s: Couldn't seek to tty %d slot in %s", "__func__", "tty", "UTMP_FILE"},
    {"%s: error writing %s: %s", "__func__", "UTMP_FILE", "strerror"},
    {"%s: utmp_write_library() failed", "__func__"},
    {"%s: utmp_write_direct() failed", "__func__"},
    {"%s: invalid type field", "__func__"},
    {"%s: not implemented!", "__func__"},
    {"%s: problem writing %s: %s", "__func__", "WTMP_FILE", "strerror"},
    {"%s: problem opening %s: %s", "__func__", "WTMP_FILE", "strerror"},
    {"%s: couldn't stat %s: %s", "__func__", "WTMP_FILE", "strerror"},
    {"%s: read of %s failed: %s", "__func__", "WTMP_FILE", "strerror"},
    {"%s: logout() returned an error", "__func__"},
    {"%s: Invalid type field", "__func__"},
    {"%s: Couldn't stat %s: %s", "__func__", "LASTLOG_FILE", "strerror"},
    {"%s: %.100s is not a file or directory!", "__func__", "LASTLOG_FILE"},
    {"%s: %s->lseek(): %s", "__func__", "lastlog_file", "strerror"},
    {"%s: Error writing to %s: %s", "__func__", "LASTLOG_FILE", "strerror"},
    {"%s: fstat of %s failed: %s", "__func__", "_PATH_BTMP", "strerror"},
    {"Excess permission or bad ownership on file %s", "_PATH_BTMP"},

    -- openssh-portable/auth-krb5.c
    {"mkstemp(): %.100s", "strerror"},
    {"fchmod(): %.100s", "strerror"},

    -- openssh-portable/auth2-hostbased.c
    {"%s: key type %s not in HostbasedAcceptedKeyTypes", "__func__", "sshkey_type"},
    {"userauth_hostbased mismatch: client sends %s, but we resolve %s to %s", "chost", "ipaddr", "resolvedname"},
}

return M

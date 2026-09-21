#include "AuditToken.h"
#include <bsm/libbsm.h>
#include <string.h>
uid_t ccw_audit_euid(const void *bytes, size_t length) {
    audit_token_t token;
    if (!bytes || length != sizeof(token)) return (uid_t)-1;
    memcpy(&token, bytes, sizeof(token));
    return audit_token_to_euid(token);
}

int32_t ccw_audit_pid(const void *bytes, size_t length) {
    if (length != sizeof(audit_token_t)) return -1;
    audit_token_t token;
    memcpy(&token, bytes, sizeof(token));
    return audit_token_to_pid(token);
}

#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <stdlib.h>

int32_t ccw_owns_loopback_socket(int32_t pid, uint16_t local_port, uint16_t remote_port, int32_t listening) {
    int required = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (required <= 0 || required > (int)(4096 * sizeof(struct proc_fdinfo))) return 0;
    int capacity = required + 128 * sizeof(struct proc_fdinfo);
    struct proc_fdinfo *fds = calloc(1, capacity);
    if (!fds) return 0;
    int length = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, capacity);
    int found = 0;
    if (length > 0 && length <= capacity && length % sizeof(struct proc_fdinfo) == 0) {
        for (int i = 0; i < length / (int)sizeof(struct proc_fdinfo); i++) {
            if (fds[i].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
            struct socket_fdinfo socket;
            if (proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDSOCKETINFO, &socket, sizeof(socket)) != sizeof(socket)) continue;
            if (socket.psi.soi_kind != SOCKINFO_TCP || socket.psi.soi_family != AF_INET) continue;
            struct tcp_sockinfo *tcp = &socket.psi.soi_proto.pri_tcp;
            struct in_sockinfo *in = &tcp->tcpsi_ini;
            if (ntohs((uint16_t)in->insi_lport) != local_port || ntohl(in->insi_laddr.ina_46.i46a_addr4.s_addr) != INADDR_LOOPBACK) continue;
            if (listening) {
                if (tcp->tcpsi_state == TSI_S_LISTEN) { found = 1; break; }
            } else if ((tcp->tcpsi_state == TSI_S_ESTABLISHED || tcp->tcpsi_state == TSI_S__CLOSE_WAIT || tcp->tcpsi_state == TSI_S_FIN_WAIT_1 || tcp->tcpsi_state == TSI_S_FIN_WAIT_2) && ntohs((uint16_t)in->insi_fport) == remote_port
                       && ntohl(in->insi_faddr.ina_46.i46a_addr4.s_addr) == INADDR_LOOPBACK) { found = 1; break; }
        }
    }
    free(fds);
    return found;
}

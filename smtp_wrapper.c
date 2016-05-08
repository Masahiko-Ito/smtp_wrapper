/*
 * smtp_wrapper (spam filtering support daemon) 
 *   by "Masahiko Ito" <m-ito@mbox.kyoto-inet.or.jp>
 *
 * Ver. 0.1 2006/01/23 release
 */
#include <stdio.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>
#include <ctype.h>
#include <libgen.h>
#include <syslog.h>

#define SW_VERSION	"0.1"

#define SS_INITMSG	(0)
#define SS_RECVCOM	(1)
#define SS_RECVMSG	(2)
#define SS_CHKMSG	(3)
#define SS_OUTMSG	(4)
#define SS_RESNORM	(5)
#define SS_RESDATA	(6)
#define SS_RESPERIOD	(7)
#define SS_RESQUIT	(8)
#define SS_EXIT		(9)

#define BUF_LEN (1024 * 16)
#define HOST_LEN (256)
#define PATH_LEN (256)

void  SigTrap();

int ChildCount = 0;

/*
 * main routine
 *
 *  Usage : smtp_wrapper -mh hostname -mp port -q backlog -sh smtpserver_hostname -sp smtpserver_port -t timeout_sec -d delay_sec -f filter -cm child_max -F
 */
int main(argc, argv, arge)
    int  argc;
    char *argv[];
    char *arge[];
{
    int i;
    int  socket_accept_client, socket_rw_client;
    char hostname[HOST_LEN], smtp_hostname[HOST_LEN];
    char filter[PATH_LEN];
    int port, smtp_port, backlog;
    struct timeval tv, *ptr_tv;
    int delay_sec;
    struct sockaddr_in client_sockaddr_in;
    int forground_sw;
    int child_max;
    int left_sleep;

/*
 * start message
 */
    syslog(LOG_MAIL|LOG_INFO, "[%d] smtp_wrapper ver. %-s started\n", getpid(), SW_VERSION);
/*
 * initialize arguments
 */
    bzero(hostname, sizeof(hostname));
    strncpy(hostname, "", strlen(""));
    port = 25;
    backlog = 5;
    bzero(smtp_hostname, sizeof(smtp_hostname));
    strncpy(smtp_hostname, "localhost", strlen("localhost"));
    smtp_port = 8025;
    bzero(filter, sizeof(filter));
    strncpy(filter, "/usr/local/smtp_wrapper/smtp_filter", strlen("/usr/local/smtp_wrapper/smtp_filter"));
    ptr_tv = (struct timeval *)NULL;
    delay_sec = 0;
    forground_sw = 0;
    child_max = 10;

    for (i = 1; i < argc; i++){
        if (strncmp(argv[i], "-mh", strlen("-mh")) == 0){
            i++;
            bzero(hostname, sizeof(hostname));
            strncpy(hostname, argv[i], sizeof(hostname) - 1);
        }else if (strncmp(argv[i], "-mp", strlen("-mp")) == 0){
            i++;
            port = atoi(argv[i]);
        }else if (strncmp(argv[i], "-q", strlen("-q")) == 0){
            i++;
            backlog = atoi(argv[i]);
        }else if (strncmp(argv[i], "-sh", strlen("-sh")) == 0){
            i++;
            bzero(smtp_hostname, sizeof(smtp_hostname));
            strncpy(smtp_hostname, argv[i], sizeof(smtp_hostname) - 1);
        }else if (strncmp(argv[i], "-sp", strlen("-sp")) == 0){
            i++;
            smtp_port = atoi(argv[i]);
        }else if (strncmp(argv[i], "-t", strlen("-t")) == 0){
            i++;
            tv.tv_sec = atoi(argv[i]);
            tv.tv_usec = 0;
            ptr_tv = &tv;
        }else if (strncmp(argv[i], "-d", strlen("-d")) == 0){
            i++;
            delay_sec = atoi(argv[i]);
        }else if (strncmp(argv[i], "-f", strlen("-f")) == 0){
            i++;
            bzero(filter, sizeof(filter));
            strncpy(filter, argv[i], sizeof(filter) - 1);
        }else if (strncmp(argv[i], "-cm", strlen("-cm")) == 0){
            i++;
            child_max = atoi(argv[i]);
        }else if (strncmp(argv[i], "-F", strlen("-F")) == 0){
            forground_sw = 1;
        }else if (strncmp(argv[i], "-h", strlen("-h")) == 0 ||
                  strncmp(argv[i], "--help", strlen("--help")) == 0){
            show_help();
            exit(0);
        }else{
            fprintf(stderr, "Bad option (%-s)\n", argv[i]);
            show_help();
            exit(1);
        }
    }

/*
 * go into background
 */
    if (forground_sw == 0){
        if (fork() == 0){
            /* do nothing */;
        }else{
            exit(0);
        }
    }

/*
 * init environ
 */
    chdir ("/");
    umask(077);

/*
 * initialize signal
 */
    init_signal();

/*
 * initialize value
 */
    errno = 0;


/*
 * open socket for client
 */
    if ((socket_accept_client = open_accept_socket_for_client(hostname, port, backlog)) == -1){
        fprintf(stderr, "[%d] Error open_accept_socket_for_client(%-s, %d, %d) : %-s\n", getpid(), hostname, port, backlog, strerror(errno));
        exit(1);
    }

/*
 * accept client
 */
    if ((socket_rw_client = open_rw_socket_for_client(socket_accept_client, &client_sockaddr_in)) == -1){
        fprintf(stderr, "[%d] Error open_rw_socket_for_client(%d) : %-s\n", getpid(), socket_accept_client, strerror(errno));
        exit(1);
    }

    for (;;){
/*
 * wait terminated process
 */
        sweep_zombi();

        if (ChildCount > child_max){
            syslog(LOG_MAIL|LOG_INFO, "[%d] ChildCount exceeds child_max(%d), so sleep into %d sec\n", getpid(), child_max, delay_sec);

            left_sleep = sleep(delay_sec);
            while (left_sleep > 0){
                left_sleep = sleep(left_sleep);
            }
            sweep_zombi();

            while (ChildCount > (child_max / 2)){
                syslog(LOG_MAIL|LOG_INFO, "[%d] ChildCount exceeds half of child_max(%d), so sleep into %d sec\n", getpid(), child_max, delay_sec);

                left_sleep = sleep(delay_sec);
                while (left_sleep > 0){
                    left_sleep = sleep(left_sleep);
                }
                sweep_zombi();
            }

            syslog(LOG_MAIL|LOG_INFO, "[%d] ChildCount become under half of child_max(%d), so wakeup\n", getpid(), child_max);
        }

        if (fork() == 0){

            left_sleep = sleep(delay_sec);
            while (left_sleep > 0){
                left_sleep = sleep(left_sleep);
            }
    
            close(socket_accept_client);
            communicate_smtpdaemon(smtp_hostname, smtp_port, socket_rw_client, ptr_tv, filter, &client_sockaddr_in);
            exit(0);
        }else{
            ChildCount++;
            close(socket_rw_client);
        }
/*
 * accept client
 */
        if ((socket_rw_client = open_rw_socket_for_client(socket_accept_client, &client_sockaddr_in)) == -1){
            fprintf(stderr, "[%d] Error open_rw_socket_for_client(%d) : %-s\n", getpid(), socket_accept_client, strerror(errno));
            exit(1);
        }
    }

    exit(0);
}

/*
 * initialize signal trap handler
 */
int init_signal()
{
    signal(SIGTERM, SigTrap);
    signal(SIGCHLD, SigTrap);

    signal(SIGHUP, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);
    signal(SIGQUIT, SIG_IGN);
    signal(SIGTSTP, SIG_IGN);
    signal(SIGTTIN, SIG_IGN);
    signal(SIGTTOU, SIG_IGN);
    signal(SIGTTOU, SIG_IGN);

    return 0;
}

/*
 * signal trap
 */
void  SigTrap(sig)
    int  sig;
{
    int  status;

    errno = 0;

    switch (sig){
    case SIGTERM:
        syslog(LOG_MAIL|LOG_INFO, "[%d] SIGTERM catched and normal shutdown\n", getpid());
        exit(0);
        break;
    case SIGCHLD:
        break;
    default:
        syslog(LOG_MAIL|LOG_INFO, "[%d] signal(%d) catched and exit\n", getpid(), sig);
        exit(0);
        break;
    }
    signal(sig, SigTrap);
}

/*
 * open socket to wait accepting from client
 */
int open_accept_socket_for_client(hostname, port, backlog)
    char *hostname;
    int  port;
    int backlog;
{
    struct hostent *my_hostent;
    struct sockaddr_in my_sockaddr_in;
    int s;

    errno = 0;

/*
 * make socket
 */
    bzero((char *)&my_sockaddr_in, sizeof my_sockaddr_in);
    my_sockaddr_in.sin_family = AF_INET;
    my_sockaddr_in.sin_port = htons(port);
    if (*hostname == '\0'){
        my_sockaddr_in.sin_addr.s_addr = htonl(INADDR_ANY);
    }else{
        if ((my_hostent = gethostbyname(hostname)) == (struct hostent *)NULL){
            syslog(LOG_MAIL|LOG_INFO, "[%d] open_accept_socket_for_client : gethostbyname(%-s) : %-s\n", getpid(), hostname, strerror(errno));
            return -1;
        }
        bcopy(my_hostent->h_addr, (char *)&my_sockaddr_in.sin_addr, my_hostent->h_length);
    }

/*
 * ready socket
 */
    if ((s = socket(AF_INET, SOCK_STREAM, 0)) == -1){
        syslog(LOG_MAIL|LOG_INFO, "[%d] open_accept_socket_for_client : socket : %-s\n", getpid(), strerror(errno));
        return -1;
    }
    if (bind(s, (struct sockaddr *)&my_sockaddr_in, sizeof my_sockaddr_in) == -1){
        syslog(LOG_MAIL|LOG_INFO, "[%d] open_accept_socket_for_client : bind : %-s\n", getpid(), strerror(errno));
        return -1;
    }

    if (listen(s, backlog) == -1){
        syslog(LOG_MAIL|LOG_INFO, "[%d] open_accept_socket_for_client : listen : %-s\n", getpid(), strerror(errno));
        return -1;
    }

    return s;
}

/*
 * open socket to communicate messages between client and me
 */
int open_rw_socket_for_client(sac, csa)
    int sac;
    struct sockaddr_in *csa;
{
    struct sockaddr_in client_sockaddr_in;
    socklen_t client_socklen_t;
    int s;

    errno = 0;

    client_socklen_t = sizeof client_sockaddr_in;
    s = accept(sac, (struct sockaddr *)&client_sockaddr_in, &client_socklen_t);
    while (s < 0 && errno == EINTR){
        client_socklen_t = sizeof client_sockaddr_in;
        s = accept(sac, (struct sockaddr *)&client_sockaddr_in, &client_socklen_t);
    }
    memcpy(csa, &client_sockaddr_in, sizeof client_sockaddr_in);

    return s;
}

/*
 * open socket to communicate messages between smtp-daemon and me
 */
int open_rw_socket_for_server(hostname, port)
    char *hostname;
    int  port;
{
    struct hostent *server_hostent;
    struct sockaddr_in  server_sockaddr_in;
    int s;

    errno = 0;

    if ((server_hostent = gethostbyname(hostname)) == (struct hostent *)NULL){
        syslog(LOG_MAIL|LOG_INFO, "[%d] open_rw_socket_for_server : gethostbyname(%-s) : %-s\n", getpid(), hostname, strerror(errno));
        return -1;
    }
    if ((s = socket(AF_INET,SOCK_STREAM, 0)) < 0){
        syslog(LOG_MAIL|LOG_INFO, "[%d] open_rw_socket_for_server : socket : %-s\n", getpid(), strerror(errno));
        return -1;
    }
    memset((char *)&server_sockaddr_in, 0, sizeof(server_sockaddr_in));
    server_sockaddr_in.sin_family = AF_INET;
    server_sockaddr_in.sin_port = htons(port);
    memcpy((char *)&server_sockaddr_in.sin_addr, server_hostent->h_addr, server_hostent->h_length);
    if (connect(s, (struct sockaddr *)&server_sockaddr_in, sizeof(server_sockaddr_in)) == -1){
        syslog(LOG_MAIL|LOG_INFO, "[%d] open_rw_socket_for_server : connect : %-s\n", getpid(), strerror(errno));
        return -1;
    }

    return s;
}

/*
 * sweep zombi(filter)
 */
int sweep_zombi()
{
    int ret;
    int status;

    errno = 0;

    ret = waitpid(-1, &status, WNOHANG);
    while (ret > 0){
        ChildCount--;
        ret = waitpid(-1, &status, WNOHANG);
    }

    return 0;
}

/*
 * communicate smtpdaemon
 */
int communicate_smtpdaemon(hostname, port, socket_rw_client, ptr_tv, filter, csa)
    char *hostname;
    int port;
    int socket_rw_client;
    struct timeval *ptr_tv;
    char *filter;
    struct sockaddr_in *csa;
{
    char client_buf[BUF_LEN];
    char smtpdaemon_buf[BUF_LEN];
    char filter_buf[BUF_LEN];

    char read_client_buf[BUF_LEN];
    char read_smtpdaemon_buf[BUF_LEN];
    char read_filter_buf[BUF_LEN];

    fd_set fdset;
    int select_num, max_fd;

    int socket_rw_smtpdaemon;
    int ret_client, ret_smtpdaemon, ret_filter;

    int pipe_p2c[2],pipe_c2p[2];
    int fd_r_filter, fd_w_filter;

    int sw_fd_r_filter, sw_socket_rw_smtpdaemon, sw_socket_rw_client;
    int smtp_status;

    struct timeval tv;

/*
 * open socket to smtp daemon
 */
    if ((socket_rw_smtpdaemon = open_rw_socket_for_server(hostname, port)) == -1){
        syslog(LOG_MAIL|LOG_INFO, "[%d] communicate_smtpdaemon : open_rw_socket_for_server(%-s, %d) : %-s\n", getpid(), hostname, port, strerror(errno));
        return -1;
    }

    bzero(read_client_buf, BUF_LEN);
    bzero(read_smtpdaemon_buf, BUF_LEN);

    fd_r_filter = -1;
    fd_w_filter = -1;
    smtp_status = SS_INITMSG;

    while (smtp_status != SS_EXIT && socket_rw_client > 0 && socket_rw_smtpdaemon > 0){
/*
 * wait terminated process
 */
        sweep_zombi();

/*
 * set filter read flag
 */
        if (smtp_status == SS_INITMSG){
            sw_fd_r_filter = 0;
            sw_socket_rw_smtpdaemon = 1;
            sw_socket_rw_client = 0;
        }else if (smtp_status == SS_RECVCOM){
            sw_fd_r_filter = 0;
            sw_socket_rw_smtpdaemon = 0;
            sw_socket_rw_client = 1;
        }else if (smtp_status == SS_RESNORM){
            sw_fd_r_filter = 0;
            sw_socket_rw_smtpdaemon = 1;
            sw_socket_rw_client = 0;
        }else if (smtp_status == SS_RESQUIT){
            sw_fd_r_filter = 0;
            sw_socket_rw_smtpdaemon = 1;
            sw_socket_rw_client = 0;
        }else if (smtp_status == SS_RECVMSG){
            sw_fd_r_filter = 1;
            sw_socket_rw_smtpdaemon = 0;
            sw_socket_rw_client = 1;
        }else if (smtp_status == SS_CHKMSG){
            sw_fd_r_filter = 1;
            sw_socket_rw_smtpdaemon = 0;
            sw_socket_rw_client = 0;
        }else if (smtp_status == SS_RESDATA){
            sw_fd_r_filter = 0;
            sw_socket_rw_smtpdaemon = 1;
            sw_socket_rw_client = 0;
        }else if (smtp_status == SS_OUTMSG){
            sw_fd_r_filter = 1;
            sw_socket_rw_smtpdaemon = 0;
            sw_socket_rw_client = 0;
        }else if (smtp_status == SS_RESPERIOD){
            sw_fd_r_filter = 0;
            sw_socket_rw_smtpdaemon = 1;
            sw_socket_rw_client = 0;
        }else{
            sw_fd_r_filter = 0;
            sw_socket_rw_smtpdaemon = 0;
            sw_socket_rw_client = 0;
        }
        

/*
 * wait messages by select
 */
        FD_ZERO(&fdset);
        if ((socket_rw_client > 0 && sw_socket_rw_client == 1 && read_client_buf[0] != '\0') ||
            (socket_rw_smtpdaemon > 0 && sw_socket_rw_smtpdaemon == 1 && read_smtpdaemon_buf[0] != '\0') ||
            (fd_r_filter > 0 && sw_fd_r_filter == 1 && read_filter_buf[0] != '\0')){
            select_num = 0;
            if (socket_rw_client > 0 && sw_socket_rw_client == 1 && read_client_buf[0] != '\0'){
                select_num++;
            }
            if (socket_rw_smtpdaemon > 0 && sw_socket_rw_smtpdaemon == 1 && read_smtpdaemon_buf[0] != '\0'){
                select_num++;
            }
            if (fd_r_filter > 0 && sw_fd_r_filter == 1 && read_filter_buf[0] != '\0'){
                select_num++;
            }
        }else{
/*
 * set file descriptor to select
 */
            if (socket_rw_client > 0 && sw_socket_rw_client == 1){
                FD_SET(socket_rw_client, &fdset);
            }
            if (socket_rw_smtpdaemon > 0 && sw_socket_rw_smtpdaemon == 1){
                FD_SET(socket_rw_smtpdaemon, &fdset);
            }
            if (fd_r_filter > 0 && sw_fd_r_filter == 1){
                FD_SET(fd_r_filter, &fdset);
            }
/*
 * set num of file descriptor to select
 */
            max_fd = -1;
            if (socket_rw_client > max_fd && sw_socket_rw_client == 1){
                max_fd = socket_rw_client;
            }
            if (socket_rw_smtpdaemon > max_fd && sw_socket_rw_smtpdaemon == 1){
                max_fd = socket_rw_smtpdaemon;
            }
            if (fd_r_filter > max_fd && sw_fd_r_filter == 1){
                max_fd = fd_r_filter;
            }

            select_num = -1;
            while (select_num < 0){
                errno = 0;
                if (ptr_tv == (struct timeval *)NULL){
                    select_num = select(max_fd + 1, &fdset, NULL, NULL, NULL);
                }else{
                    tv.tv_sec = ptr_tv->tv_sec;
                    tv.tv_usec = 0;
                    select_num = select(max_fd + 1, &fdset, NULL, NULL, &tv);
                }
                if (select_num < 0){
                    if (errno != EINTR){
                        break;
                    }
                }
            }
        }

        if (select_num == 0){
            syslog(LOG_MAIL|LOG_INFO, "[%d] communicate_smtpdaemon : select timeout : %-s\n", getpid(), strerror(errno));

            bzero(client_buf, BUF_LEN);
            strncpy(client_buf, "451 Requested action aborted: local error in processing(1 select timeout)\r\n", sizeof(client_buf) - 1);
            ret_client = sock_write(socket_rw_client, client_buf, strlen(client_buf));

            syslog(LOG_MAIL|LOG_INFO, "[%d] 451 Requested action aborted: local error in processing(1 select timeout)\n", getpid());

            smtp_status = SS_EXIT;
        }else if (select_num < 0){
/*
 * select return negative value when SIGPIPE occured(?), So IGNORE
 */
            syslog(LOG_MAIL|LOG_INFO, "[%d] communicate_smtpdaemon : select error : %-s\n", getpid(), strerror(errno));
        }

        if (smtp_status == SS_INITMSG){

            if (FD_ISSET(socket_rw_smtpdaemon, &fdset) || read_smtpdaemon_buf[0] != '\0'){
                bzero(smtpdaemon_buf, BUF_LEN);
                if ((ret_smtpdaemon = sock_read(socket_rw_smtpdaemon, smtpdaemon_buf, BUF_LEN - 1, read_smtpdaemon_buf)) < 0){
                    close(socket_rw_smtpdaemon);
                    socket_rw_smtpdaemon = -1;
                }
                if ((ret_client = sock_write(socket_rw_client, smtpdaemon_buf, strlen(smtpdaemon_buf))) < 0){
                    close(socket_rw_client);
                    socket_rw_client = -1;
                    syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write socket_rw_client error in SS_INITMSG\n", getpid());
                }

                smtp_status = SS_RECVCOM;
            }

        }else if (smtp_status == SS_RECVCOM){

            if (FD_ISSET(socket_rw_client, &fdset) || read_client_buf[0] != '\0'){

                bzero(client_buf, BUF_LEN);
                if ((ret_client = sock_read(socket_rw_client, client_buf, BUF_LEN - 1, read_client_buf)) < 0){
                    close(socket_rw_client);
                    socket_rw_client = -1;
                }

                if (string_compare(client_buf, "QUIT\r\n", strlen("QUIT\r\n")) != 0 &&
                    string_compare(client_buf, "QUIT\n", strlen("QUIT\n")) != 0){

                    if (fd_r_filter < 0){
/*
 * close pipe
 */
                       close(fd_w_filter);
                       fd_w_filter = -1;
        
                       close(fd_r_filter);
                       fd_r_filter = -1;
        
/*
 * create pipe for filter
 */
                        if (pipe(pipe_c2p) < 0){
                            syslog(LOG_MAIL|LOG_INFO, "[%d] communicate_smtpdaemon : pipe_c2p : %-s\n", getpid(), strerror(errno));
                            return -1;
                        }
                        if (pipe(pipe_p2c) < 0){
                            syslog(LOG_MAIL|LOG_INFO, "[%d] communicate_smtpdaemon : pipe_p2c : %-s\n", getpid(), strerror(errno));
                            return -1;
                        }
/*
 * execute filter
 */
                        if (fork() == 0){
                            close(socket_rw_client);
                            close(socket_rw_smtpdaemon);
                            execute_filter(filter, pipe_p2c, pipe_c2p, csa);
                            exit(0);
                        }else{
                            close(pipe_p2c[0]);
                            close(pipe_c2p[1]);
                            fd_w_filter = pipe_p2c[1];
                            fd_r_filter = pipe_c2p[0];
                        }
        
                        bzero(read_filter_buf, BUF_LEN);
                    }
                }

                if (string_compare(client_buf, "QUIT\r\n", strlen("QUIT\r\n")) != 0 &&
                    string_compare(client_buf, "QUIT\n", strlen("QUIT\n")) != 0){
                    if (fd_w_filter > 0){
                        if ((ret_filter = sock_write(fd_w_filter, client_buf, strlen(client_buf))) < 0){
                            close(fd_w_filter);
                            fd_w_filter = -1;
                            syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write fd_w_filter error in SS_RECVCOM\n", getpid());
                        }
                    }
                }

                if (string_compare(client_buf, "DATA\r\n", strlen("DATA\r\n")) == 0 ||
                    string_compare(client_buf, "DATA\n", strlen("DATA\n")) == 0){

                    bzero(client_buf, BUF_LEN);
                    strncpy(client_buf, "354 Hey come on spammers!\r\n", sizeof(client_buf) - 1);
                    if ((ret_client = sock_write(socket_rw_client, client_buf, strlen(client_buf))) < 0){
                        close(socket_rw_client);
                        socket_rw_client = -1;
                        syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write socket_rw_client error in SS_RECVCOM\n", getpid());
                    }

                    smtp_status = SS_RECVMSG;

                }else if (string_compare(client_buf, "QUIT\r\n", strlen("QUIT\r\n")) == 0 ||
                          string_compare(client_buf, "QUIT\n", strlen("QUIT\n")) == 0){

                    if ((ret_smtpdaemon = sock_write(socket_rw_smtpdaemon, client_buf, strlen(client_buf))) < 0){
                        close(socket_rw_smtpdaemon);
                        socket_rw_smtpdaemon = -1;
                        syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write socket_rw_smtpdaemon error in SS_RECVCOM(1)\n", getpid());
                    }
                    smtp_status = SS_RESQUIT;

                }else{

                    if ((ret_smtpdaemon = sock_write(socket_rw_smtpdaemon, client_buf, strlen(client_buf))) < 0){
                        close(socket_rw_smtpdaemon);
                        socket_rw_smtpdaemon = -1;
                        syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write socket_rw_smtpdaemon error in SS_RECVCOM(2)\n", getpid());
                    }
                    smtp_status = SS_RESNORM;

                }
            }

        }else if (smtp_status == SS_RESNORM){

            if (FD_ISSET(socket_rw_smtpdaemon, &fdset) || read_smtpdaemon_buf[0] != '\0'){
                bzero(smtpdaemon_buf, BUF_LEN);
                if ((ret_smtpdaemon = sock_read(socket_rw_smtpdaemon, smtpdaemon_buf, BUF_LEN - 1, read_smtpdaemon_buf)) < 0){
                    close(socket_rw_smtpdaemon);
                    socket_rw_smtpdaemon = -1;
                }
                if ((ret_client = sock_write(socket_rw_client, smtpdaemon_buf, strlen(smtpdaemon_buf))) < 0){
                    close(socket_rw_client);
                    socket_rw_client = -1;
                    syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write socket_rw_client error in SS_RESNORM\n", getpid());
                }

                if (smtpdaemon_buf[3] == '-'){
                    smtp_status = SS_RESNORM;
                }else{
                    smtp_status = SS_RECVCOM;
                }
            }

        }else if (smtp_status == SS_RESQUIT){

            if (FD_ISSET(socket_rw_smtpdaemon, &fdset) || read_smtpdaemon_buf[0] != '\0'){
                bzero(smtpdaemon_buf, BUF_LEN);
                if ((ret_smtpdaemon = sock_read(socket_rw_smtpdaemon, smtpdaemon_buf, BUF_LEN - 1, read_smtpdaemon_buf)) < 0){
                    close(socket_rw_smtpdaemon);
                    socket_rw_smtpdaemon = -1;
                }
                if ((ret_client = sock_write(socket_rw_client, smtpdaemon_buf, strlen(smtpdaemon_buf))) < 0){
                    close(socket_rw_client);
                    socket_rw_client = -1;
                    syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write socket_rw_client error in SS_RESQUIT\n", getpid());
                }

                smtp_status = SS_EXIT;
            }

        }else if (smtp_status == SS_RECVMSG){

            if (FD_ISSET(socket_rw_client, &fdset) || read_client_buf[0] != '\0'){
                bzero(client_buf, BUF_LEN);
                if ((ret_client = sock_read(socket_rw_client, client_buf, BUF_LEN - 1, read_client_buf)) < 0){
                    close(socket_rw_client);
                    socket_rw_client = -1;
                }
                if (fd_w_filter > 0){
                    if ((ret_filter = sock_write(fd_w_filter, client_buf, strlen(client_buf))) < 0){
                        close(fd_w_filter);
                        fd_w_filter = -1;
                        syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write fd_w_filter error in SS_RECVMSG\n", getpid());
                    }
                }

                if (string_compare(client_buf, ".\r\n", strlen(".\r\n")) == 0 ||
                    string_compare(client_buf, ".\n", strlen(".\n")) == 0){
                    close(fd_w_filter);
                    fd_w_filter = -1;

                    smtp_status = SS_CHKMSG;
                }else{
                    smtp_status = SS_RECVMSG;
                }
            }

            if (FD_ISSET(fd_r_filter, &fdset) || read_filter_buf[0] != '\0'){
                bzero(filter_buf, BUF_LEN);
                ret_filter = sock_read(fd_r_filter, filter_buf, BUF_LEN - 1, read_filter_buf);

                bzero(client_buf, BUF_LEN);
                strncpy(client_buf, "450 This message was accepted partly but it looks like spam, rejected(2)\r\n", sizeof(client_buf) - 1);
                ret_client = sock_write(socket_rw_client, client_buf, strlen(client_buf));

                syslog(LOG_MAIL|LOG_INFO, "[%d] 450 This message was accepted partly but it looks like spam, rejected(2) filter return=(%-s)\n", getpid(), filter_buf);

                smtp_status = SS_EXIT;
            }

        }else if (smtp_status == SS_CHKMSG){

            if (FD_ISSET(fd_r_filter, &fdset) || read_filter_buf[0] != '\0'){
                bzero(filter_buf, BUF_LEN);
                if ((ret_filter = sock_read(fd_r_filter, filter_buf, BUF_LEN - 1, read_filter_buf)) < 0){
                    close(fd_r_filter);
                    fd_r_filter = -1;
                }
                if (string_compare(filter_buf, "DATA\r\n", strlen("DATA\r\n")) == 0 ||
                    string_compare(filter_buf, "DATA\n", strlen("DATA\n")) == 0){
                    if ((ret_smtpdaemon = sock_write(socket_rw_smtpdaemon, filter_buf, strlen(filter_buf))) < 0){
                        close(socket_rw_smtpdaemon);
                        socket_rw_smtpdaemon = -1;
                        syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write socket_rw_smtpdaemon error in SS_CHKMSG\n", getpid());
                    }

                    smtp_status = SS_RESDATA;
                }else{
                    bzero(client_buf, BUF_LEN);
                    strncpy(client_buf, "450 This message was accepted all but it looks like spam, rejected(3)\r\n", sizeof(client_buf) - 1);
                    if ((ret_client = sock_write(socket_rw_client, client_buf, strlen(client_buf))) < 0){
                        close(socket_rw_client);
                        socket_rw_client = -1;
                        syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write socket_rw_client error in SS_CHKMSG\n", getpid());
                    }

                    syslog(LOG_MAIL|LOG_INFO, "[%d] 450 This message was accepted all but it looks like spam, rejected(3) filter return=(%-s)\n", getpid(), filter_buf);

                    smtp_status = SS_EXIT;
                }
            }

        }else if (smtp_status == SS_RESDATA){

            if (FD_ISSET(socket_rw_smtpdaemon, &fdset) || read_smtpdaemon_buf[0] != '\0'){
                bzero(smtpdaemon_buf, BUF_LEN);
                if ((ret_smtpdaemon = sock_read(socket_rw_smtpdaemon, smtpdaemon_buf, BUF_LEN - 1, read_smtpdaemon_buf)) < 0){
                    close(socket_rw_smtpdaemon);
                    socket_rw_smtpdaemon = -1;
                }
                if (string_compare(smtpdaemon_buf, "354", strlen("354")) == 0){
                    smtp_status = SS_OUTMSG;
                }else{
                    bzero(client_buf, BUF_LEN);
                    strncpy(client_buf, "451 server error, rejected(4)\r\n", sizeof(client_buf) - 1);
                    ret_client = sock_write(socket_rw_client, client_buf, strlen(client_buf));

                    syslog(LOG_MAIL|LOG_INFO, "[%d] 451 server error, rejected(4)\n", getpid());

                    smtp_status = SS_EXIT;
                }
            }

        }else if (smtp_status == SS_OUTMSG){

            if (FD_ISSET(fd_r_filter, &fdset) || read_filter_buf[0] != '\0'){
                bzero(filter_buf, BUF_LEN);
                if ((ret_filter = sock_read(fd_r_filter, filter_buf, BUF_LEN - 1, read_filter_buf)) < 0){
                    close(fd_r_filter);
                    fd_r_filter = -1;
                }
                if ((ret_smtpdaemon = sock_write(socket_rw_smtpdaemon, filter_buf, strlen(filter_buf))) < 0){
                    close(socket_rw_smtpdaemon);
                    socket_rw_smtpdaemon = -1;
                    syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write socket_rw_smtpdaemon error in SS_OUTMSG\n", getpid());
                }

                if (string_compare(filter_buf, ".\r\n", strlen(".\r\n")) == 0 ||
                    string_compare(filter_buf, ".\n", strlen(".\n")) == 0){
                    close(fd_r_filter);
                    fd_r_filter = -1;

                    smtp_status = SS_RESPERIOD;
                }else{
                    smtp_status = SS_OUTMSG;
                }
            }

        }else if (smtp_status == SS_RESPERIOD){

            if (FD_ISSET(socket_rw_smtpdaemon, &fdset) || read_smtpdaemon_buf[0] != '\0'){
                bzero(smtpdaemon_buf, BUF_LEN);
                if ((ret_smtpdaemon = sock_read(socket_rw_smtpdaemon, smtpdaemon_buf, BUF_LEN - 1, read_smtpdaemon_buf)) < 0){
                    close(socket_rw_smtpdaemon);
                    socket_rw_smtpdaemon = -1;
                }
                if ((ret_client = sock_write(socket_rw_client, smtpdaemon_buf, strlen(smtpdaemon_buf))) < 0){
                    close(socket_rw_client);
                    socket_rw_client = -1;
                    syslog(LOG_MAIL|LOG_INFO, "[%d] sock_write socket_rw_client error in SS_RESPERIOD\n", getpid());
                }

                smtp_status = SS_RECVCOM;
            }

        }else if (smtp_status == SS_EXIT){

            close(socket_rw_client);
            socket_rw_client = -1;

            close(socket_rw_smtpdaemon);
            socket_rw_smtpdaemon = -1;

        }else{

            syslog(LOG_MAIL|LOG_INFO, "[%d] communicate_smtpdaemon : smtp_status error(%d) : %-s\n", smtp_status, getpid(), strerror(errno)); /* never reached */
            return -1;

        }
    }

    close(socket_rw_client);
    close(socket_rw_smtpdaemon);
    close(fd_r_filter);
    close(fd_w_filter);

    return 0;
}

/*
 * execute filter
 */
int execute_filter(filter, pipe_p2c, pipe_c2p, csa)
    char *filter;
    int *pipe_p2c;
    int *pipe_c2p;
    struct sockaddr_in *csa;
{
    int fd_null;

    setenv("SW_FROM_IP", inet_ntoa(csa->sin_addr), 1);
    close(*(pipe_p2c + 1));
    close(*(pipe_c2p + 0));
    dup2(*(pipe_p2c + 0), 0);
    dup2(*(pipe_c2p + 1), 1);
#if 0
    dup2(*(pipe_c2p + 1), 2);
#else
    if ((fd_null = open("/dev/null", O_WRONLY)) < 0){
        /* do nothing */;
    }else{
        dup2(fd_null, 2);
        close(fd_null);
    }
#endif
    close(*(pipe_p2c + 0));
    close(*(pipe_c2p + 1));
    if (execl(filter, basename(filter), NULL) < 0){
        syslog(LOG_MAIL|LOG_INFO, "[%d] execute_filter : execl(%-s) : %-s\n", filter, getpid(), strerror(errno));
        return -1;
    }

    return 0;
}

/*
 * read from socket or pipe
 */
int  sock_read(s, buf, len, read_buf)
    int   s;
    char *buf;
    int   len;
    char *read_buf;
{
    int ret, read_len, return_len;
    char *ptr_lf, *ptr_null;

    if (strchr(read_buf, '\n') == (char *)NULL){

        errno = 0;
        read_len = BUF_LEN - strlen(read_buf) - 1;
        ret = read(s, strchr(read_buf, '\0'), read_len);

        while ((ret > 0 || (ret < 0 && errno == EINTR)) &&
                read_len > 0                             &&
                strchr(read_buf, '\n') == (char *)NULL){

            errno = 0;
            if (ret > 0){
                read_len -= ret;
            }
            ret = read(s, strchr(read_buf, '\0'), read_len);
        }
    }

    if ((ptr_lf = strchr(read_buf, '\n')) == (char *)NULL){
        bzero(read_buf, BUF_LEN);
        *(buf + 0) = '\0';
        return -1; 
    }else{
        if ((ptr_lf - read_buf + 1) > len){
            bzero(read_buf, BUF_LEN);
            *(buf + 0) = '\0';
            return -1; 
        }else{
            return_len = ptr_lf - read_buf + 1;
            strncpy(buf, read_buf, return_len);

            ptr_null = strchr(read_buf, '\0');
            strncpy(read_buf, (ptr_lf + 1), ptr_null - ptr_lf);
            ptr_null = strchr(read_buf, '\0');
            bzero(ptr_null + 1, BUF_LEN - (ptr_null - read_buf + 1));
        }
    }
    return return_len;
}

/*
 * write into socket or pipe
 */
int  sock_write(s, buf, len)
    int  s;
    char *buf;
    int  len;
{
    int ret, cnt = 0, rem_cnt = (len > BUF_LEN ? BUF_LEN : len);

    errno = 0;
    if ((ret = write(s, buf + cnt, rem_cnt)) >= 0){
        cnt += ret;
        rem_cnt -= ret;
    }
    while ((ret >= 0 || (ret < 0 && errno == EINTR)) && rem_cnt > 0){
        errno = 0;
        if ((ret = write(s, buf + cnt, rem_cnt)) >= 0){
            cnt += ret;
            rem_cnt -= ret;
        }
    }
    if (rem_cnt <= 0){
        return cnt;
    }else{
        return -1;
    }
}

/*
 * string compare
 */
int string_compare(str1, str2, len)
    char *str1;
    char *str2;
    int  len;
{
    int ch1, ch2;
    int i;

    for (i = 0; i < len; i++){
        ch1 = toupper(*(str1 + i));
        ch2 = toupper(*(str2 + i));
        if (ch1 == ch2){
            if (ch1 == '\0'){
                break;
            }
        }else if (ch1 < ch2){
            return -1;
        }else{
            return 1;
        }
    }
    return 0;
}

/*
 * show help
 */
int show_help()
{
    fprintf(stderr, "Usage : smtp_wrapper [-mh hostname] [-mp port] [-q backlog] [-sh smtpserver_hostname] [-sp smtpserver_port] [-t timeout_sec] [-d delay_sec] [-f filter] [-cm child_max] [-F]\n");
    fprintf(stderr, "  -mh hostname            : my hostname [ANY]\n");
    fprintf(stderr, "  -mp port                : my port [25]\n");
    fprintf(stderr, "  -q  backlog             : socket queue number [5]\n");
    fprintf(stderr, "  -sh smtpserver_hostname : real smtp hostname [localhost]\n");
    fprintf(stderr, "  -sp smtpserver_port     : real smtp port [8025]\n");
    fprintf(stderr, "  -t  timeout_sec         : timeout second [no timeout]\n");
    fprintf(stderr, "  -d  delay_sec           : delay second for initial connection [0]\n");
    fprintf(stderr, "  -f  filter              : filter program [/usr/local/smtp_wrapper/smtp_filter]\n");
    fprintf(stderr, "  -cm child_max           : max number of connection to real smtp daemon [10]\n");
    fprintf(stderr, "  -F                      : run in foreground\n");
    return 0;
}

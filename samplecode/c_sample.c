/* a sample for using TSUBAKI API

   gcc -o c_sample c_sample.c
   ./c_sample 京都の観光名所
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <netinet/in.h>

#define SERVER "tsubaki.ixnlp.nii.ac.jp"
#define	PORT 80
#define API_ADDRESS "/api.cgi?&results=20&start=1&query="

#define BUF_SIZE 1024

/* table for uri_escape (if 1, encode it to %XX) */
static char escape_table[256] = 
{
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 
    1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 
    1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
};

/* escape URI */
char *uri_escape(unsigned char *src)
{
    int slen = strlen(src);
    int dlen = 0;
    char *dst = (char *)malloc(slen * 3 + 1);
    int i;

    for (i = 0; i < slen; i++) {
	if (escape_table[src[i]]) {
	    sprintf((char *)(dst + dlen), "%%%02X", src[i]);
	    dlen += 3;
	}
	else {
	    dst[dlen++] = src[i]; /* as it is */
	}
    }

    dst[dlen] = '\0';
    return dst;
}

/* open connection to server */
int open_connection(char *server, unsigned short port)
{
    int sfd;
    struct sockaddr_in sin;
    struct hostent *host;

    /* create a socket */
    if((sfd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
	fprintf(stderr, "socket error!\n");
	return -1;
    }

    memset(&sin, 0, sizeof(sin));
    sin.sin_port = htons(port);

    /* get an address of server */
    if ((host = gethostbyname(server)) != NULL) {
	memcpy(&sin.sin_addr.s_addr, host->h_addr, host->h_length);
	sin.sin_family = host->h_addrtype;
    }
    else if ((sin.sin_addr.s_addr = inet_addr(server)) != (in_addr_t)-1) {
	sin.sin_family = AF_INET;
    }
    else {
	fprintf(stderr, "can't get address: %s\n", server);
	return -1;
    }

    /* make a connection on the socket */
    if (connect(sfd, (struct sockaddr *)&sin, sizeof(sin)) < 0) {
	fprintf(stderr, "connect error!\n");
	close(sfd);
	return -1;
    }

    return sfd;
}

int main(int argc, char *argv[])
{
    int sfd;
    char line[BUF_SIZE], *escaped_uri;
    FILE *ifp, *ofp;

    if (argc < 2) {
	fprintf(stderr, "Usage: %s query_in_UTF-8\n", argv[0]);
	exit(1);
    }

    /* open connection to server */
    if ((sfd = open_connection(SERVER, PORT)) < 0) {
	exit(2);
    }
    
    ifp = fdopen(sfd, "r");
    ofp = fdopen(sfd, "w");

    /* escape URI */
    escaped_uri = uri_escape((unsigned char *)argv[1]);

    /* send API command */
    fprintf(ofp, "GET %s%s\n", API_ADDRESS, escaped_uri);
    fflush(ofp);
    free(escaped_uri);

    /* receive contents */
    while (fgets(line, BUF_SIZE, ifp) != NULL) {
	fputs(line, stdout);
	fflush(stdout);
    }

    fclose(ifp);
    fclose(ofp);
    close(sfd);
    exit(0);
}

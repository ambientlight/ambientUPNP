//
//  _legacy.c
//  ambientUPNP
//
//  Created by Taras Vozniuk on 1/14/16.
//  Copyright © 2016 ambientlight. All rights reserved.
//

#include "_legacy.h"

#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <net/if.h>
#include <errno.h>

int _interfaceAddressForName(char* interfaceName, struct sockaddr* interfaceAddress) {
    
    struct ifreq ifr;
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    ifr.ifr_addr.sa_family = AF_INET;
    
    strncpy(ifr.ifr_name, interfaceName, IFNAMSIZ-1);
    
    int ioctl_res;
    if ( (ioctl_res = ioctl(fd, SIOCGIFADDR, &ifr)) < 0){
        return ioctl_res;
    }
    
    close(fd);
    memcpy(interfaceAddress, &ifr.ifr_addr, sizeof(struct sockaddr));
    return 0;
}

int _ioctl(int fd, unsigned long flag, void* val) {
    return ioctl(fd, flag, val);
}



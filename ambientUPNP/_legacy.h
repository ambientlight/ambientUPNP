//
//  _legacy.h
//  ambientUPNP
//
//  Created by Taras Vozniuk on 1/14/16.
//  Copyright © 2016 ambientlight. All rights reserved.
//

#ifndef _legacy_h
#define _legacy_h

#include <stdbool.h>

int _ioctl(int fd, unsigned long flag, void* val);
int _interfaceAddressForName(char* interfaceName, struct sockaddr* interfaceAddress);

#endif /* _legacy_h */

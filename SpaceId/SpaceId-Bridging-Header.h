
#ifndef SpaceId_Bridging_Header_h
#define SpaceId_Bridging_Header_h

#import <CoreFoundation/CoreFoundation.h>
#import "Helper/PFMoveApplication.h"

id CGSCopyManagedDisplaySpaces(int conn);
id CGSCopySpacesForWindows(int conn, int mask, CFArrayRef windowIDs);
int _CGSDefaultConnection();

#endif

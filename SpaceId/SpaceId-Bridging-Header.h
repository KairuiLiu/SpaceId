
#ifndef SpaceId_Bridging_Header_h
#define SpaceId_Bridging_Header_h

#import <CoreFoundation/CoreFoundation.h>
#import "Helper/PFMoveApplication.h"

id CGSCopyManagedDisplaySpaces(int conn);
id CGSCopySpacesForWindows(int conn, int mask, CFArrayRef windowIDs);
int CGSWindowIsOrderedIn(int conn, uint32_t windowID, uint8_t *orderedIn);
int _CGSDefaultConnection();

#endif

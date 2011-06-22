//
//  RMTileStreamSource.h
//
//  Created by Justin R. Miller on 5/17/11.
//  Copyright 2011, Development Seed, Inc.
//  All rights reserved.
//  
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//  
//      * Redistributions of source code must retain the above copyright
//        notice, this list of conditions and the following disclaimer.
//  
//      * Redistributions in binary form must reproduce the above copyright
//        notice, this list of conditions and the following disclaimer in the
//        documentation and/or other materials provided with the distribution.
//  
//      * Neither the name of Development Seed, Inc., nor the names of its
//        contributors may be used to endorse or promote products derived from
//        this software without specific prior written permission.
//  
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
//  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "RMAbstractMercatorWebSource.h"

#define kTileStreamDefaultTileSize 256
#define kTileStreamDefaultMinTileZoom 0
#define kTileStreamDefaultMaxTileZoom 18
#define kTileStreamDefaultLatLonBoundingBox ((RMSphericalTrapezium){ .northeast = { .latitude =  85, .longitude =  180 }, \
                                                                     .southwest = { .latitude = -85, .longitude = -180 } })

typedef enum {
    RMTileStreamLayerTypeBaselayer = 0,
    RMTileStreamLayerTypeOverlay   = 1,
} RMTileStreamLayerType;

@interface RMTileStreamSource : RMAbstractMercatorWebSource <RMAbstractMercatorWebSource>
{
    NSDictionary *infoDictionary;
}

- (id)initWithInfo:(NSDictionary *)info;
- (id)initWithReferenceURL:(NSURL *)referenceURL;
- (RMTileStreamLayerType)layerType;
- (float)minZoomNative;
- (float)maxZoomNative;
- (BOOL)coversFullWorld;

@property (nonatomic, readonly, retain) NSDictionary *infoDictionary;

@end
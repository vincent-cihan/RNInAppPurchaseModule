//
//  RNInAppPurchaseModule.h
//  zybx
//
//  Created by 刘乙灏 on 2018/9/5.
//  Copyright © 2018年 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <React/RCTBridgeModule.h>
#import <StoreKit/StoreKit.h>

@interface RNInAppPurchaseModule : NSObject <RCTBridgeModule, SKPaymentTransactionObserver, SKProductsRequestDelegate>

@end

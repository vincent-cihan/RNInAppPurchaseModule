//
//  RNInAppPurchaseModule.m
//  zybx
//
//  Created by 刘乙灏 on 2018/9/5.
//  Copyright © 2018年 Facebook. All rights reserved.
//

////沙盒测试环境验证
//#define SANDBOX @"https://sandbox.itunes.apple.com/verifyReceipt"
////正式环境验证
//#define AppStore @"https://buy.itunes.apple.com/verifyReceipt"
/*
 内购验证凭据返回结果状态码说明
 21000 App Store无法读取你提供的JSON数据
 21002 收据数据不符合格式
 21003 收据无法被验证
 21004 你提供的共享密钥和账户的共享密钥不一致
 21005 收据服务器当前不可用
 21006 收据是有效的，但订阅服务已经过期。当收到这个信息时，解码后的收据信息也包含在返回内容中
 21007 收据信息是测试用（sandbox），但却被发送到产品环境中验证
 21008 收据信息是产品环境中使用，但却被发送到测试环境中验证
 */

#import "RNInAppPurchaseModule.h"
#import <React/RCTLog.h>

// 未验证订单持久化参数
#define kIapUnverifyOrders  @"iap_unverify_orders"

@interface SKProduct (StringPrice)  // 格式化价格字符串

@property (nonatomic, readonly) NSString *priceString;

@end

@implementation SKProduct (StringPrice)

- (NSString *)priceString {
  NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
  formatter.formatterBehavior = NSNumberFormatterBehavior10_4;
  formatter.numberStyle = NSNumberFormatterCurrencyStyle;
  formatter.locale = self.priceLocale;
  
  return [formatter stringFromNumber:self.price];
}

@end

@interface RNInAppPurchaseModule() <RCTBridgeModule, SKPaymentTransactionObserver, SKProductsRequestDelegate>

@end

@implementation RNInAppPurchaseModule
{
  NSArray *products;  // 所有可卖商品
  NSMutableDictionary *_callbacks;  // 回调，key是商品id
  RCTResponseSenderBlock _lostCallBack; // 丢单数据的重新监听回调
  NSMutableDictionary *_myProductIds;  // 业务服务器商品ID,key是商品id
}

- (instancetype)init
{
  if ((self = [super init])) {
    _callbacks = [[NSMutableDictionary alloc] init];
    _myProductIds = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()
/**
 *  添加商品购买状态监听
 *  @params:
 *        callback 针对购买过程中，App意外退出的丢单数据的回调
 */
RCT_EXPORT_METHOD(addTransactionObserverWithCallback:(RCTResponseSenderBlock)callback) {
  // 监听商品购买状态变化
  [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
  _lostCallBack = callback;
}

/**
 *  服务器验证成功，删除缓存的凭证
 */
RCT_EXPORT_METHOD(removePurchase:(NSDictionary *)purchase) {
  NSMutableArray *iapUnverifyOrdersArray = [NSMutableArray array];
  if ([[NSUserDefaults standardUserDefaults] objectForKey:kIapUnverifyOrders] != nil) {
    [iapUnverifyOrdersArray addObjectsFromArray:[[NSUserDefaults standardUserDefaults] objectForKey:kIapUnverifyOrders]];
  }
  for (NSDictionary *unverifyPurchase in iapUnverifyOrdersArray) {
    if ([unverifyPurchase[@"transactionIdentifier"] isEqualToString:purchase[@"transactionIdentifier"]]) {
      [iapUnverifyOrdersArray removeObject:unverifyPurchase];
    }
  }
  [[NSUserDefaults standardUserDefaults] setObject:[iapUnverifyOrdersArray copy] forKey:kIapUnverifyOrders];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSDictionary *)constantsToExport
{
  // 获取当前缓存的所有凭证
  NSMutableArray *iapUnverifyOrdersArray = [NSMutableArray array];
  if ([[NSUserDefaults standardUserDefaults] objectForKey:kIapUnverifyOrders] != nil) {
    [iapUnverifyOrdersArray addObjectsFromArray:[[NSUserDefaults standardUserDefaults] objectForKey:kIapUnverifyOrders]];
  }
  return @{ @"iapUnverifyOrdersArray": iapUnverifyOrdersArray };
}

/**
 *  购买某个商品
 *  @params:
 *        productIdentifier: 商品id
 *        callback： 回调，返回
 */
RCT_EXPORT_METHOD(purchaseProduct:(NSString *)productIdentifier
                  myProductId:(NSString *)myProductId
                  callback:(RCTResponseSenderBlock)callback)
{
  SKProduct *product;
  for(SKProduct *p in products)
  {
    if([productIdentifier isEqualToString:p.productIdentifier]) {
      product = p;
      break;
    }
  }
  
  if(product) {
    SKPayment *payment = [SKPayment paymentWithProduct:product];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
    _callbacks[RCTKeyForInstance(payment.productIdentifier)] = callback;
    _myProductIds[RCTKeyForInstance(payment.productIdentifier)] = myProductId;
  } else {
    callback(@[@"无效商品"]);
  }
}

/**
 *  恢复购买
 */
RCT_EXPORT_METHOD(restorePurchases:(RCTResponseSenderBlock)callback)
{
  NSString *restoreRequest = @"restoreRequest";
  _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
  [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

/**
 *  加载所有可卖的商品
 */
RCT_EXPORT_METHOD(loadProducts:(NSArray *)productIdentifiers
                  callback:(RCTResponseSenderBlock)callback)
{
  if([SKPaymentQueue canMakePayments]){
    SKProductsRequest *productsRequest = [[SKProductsRequest alloc]
                                          initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
    productsRequest.delegate = self;
    _callbacks[RCTKeyForInstance(productsRequest)] = callback;
    [productsRequest start];
  } else {
    callback(@[@"not_available"]);
  }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
 updatedTransactions:(NSArray *)transactions
{
  for (SKPaymentTransaction *transaction in transactions) {
    switch (transaction.transactionState) {
        // 购买失败
      case SKPaymentTransactionStateFailed: {
        NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
        RCTResponseSenderBlock callback = _callbacks[key];
        if (callback) {
          if(transaction.error.code != SKErrorPaymentCancelled){
            NSLog(@"购买失败");
            callback(@[@"购买失败"]);
          } else {
            NSLog(@"购买取消");
            callback(@[@"购买取消"]);
          }
          [_callbacks removeObjectForKey:key];
        } else {
          RCTLogWarn(@"No callback registered for transaction with state failed.");
        }
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        break;
      }
        // 购买成功
      case SKPaymentTransactionStatePurchased: {
        NSLog(@"购买成功");
        NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
        RCTResponseSenderBlock callback = _callbacks[key];
        
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        
        if (callback) {
          
          // 购买成功，获取凭证
          [self buyAppleStoreProductSucceedWithPaymentTransactionp:transaction callback:callback];
        } else if (_lostCallBack) {
          // 购买过程中出现意外App推出，下次启动App时的处理
          // 购买成功，获取凭证
          [self buyAppleStoreProductSucceedWithPaymentTransactionp:transaction callback:_lostCallBack];
        } else {
          RCTLogWarn(@"No callback registered for transaction with state purcahsed.");
        }
        
        break;
      }
        
        // 恢复购买
      case SKPaymentTransactionStateRestored:{
        NSLog(@"恢复购买成功");
        NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
        RCTResponseSenderBlock callback = _callbacks[key];
        if (callback) {
          callback(@[@"恢复购买成功"]);
          [_callbacks removeObjectForKey:key];
        } else {
          RCTLogWarn(@"No callback registered for transaction with state failed.");
        }
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        break;
      }
        // 正在购买
      case SKPaymentTransactionStatePurchasing:
        NSLog(@"正在购买");
        break;
        
        // 交易还在队列里面，但最终状态还没有决定
      case SKPaymentTransactionStateDeferred:
        NSLog(@"推迟");
        break;
      default:
        break;
    }
  }
}

// 苹果内购支付成功，获取凭证
- (void)buyAppleStoreProductSucceedWithPaymentTransactionp:(SKPaymentTransaction *)transaction callback:(RCTResponseSenderBlock)callback {
  NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
  NSString *transactionReceiptString= nil;
  // 验证凭据，获取到苹果返回的交易凭据
  // appStoreReceiptURL iOS7.0增加的，购买交易完成后，会将凭据存放在该地址
  NSURLRequest * appstoreRequest = [NSURLRequest requestWithURL:[[NSBundle mainBundle]appStoreReceiptURL]];
  NSError *error = nil;
  NSData * receiptData = [NSURLConnection sendSynchronousRequest:appstoreRequest returningResponse:nil error:&error];
  
  if (!receiptData) {
    callback(@[@"获取交易凭证失败"]);
  } else {
    transactionReceiptString = [receiptData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
    NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
    NSString *myProductId = _myProductIds[key];
    NSDictionary *purchase = @{
                               @"transactionIdentifier": transaction.transactionIdentifier,
                               @"productIdentifier": transaction.payment.productIdentifier,
                               @"receiptData": transactionReceiptString,
                               @"myProductId": myProductId
                               };
    // 将凭证缓存，后台验证结束后再删除
    NSMutableArray *iapUnverifyOrdersArray = [NSMutableArray array];
    if ([[NSUserDefaults standardUserDefaults] objectForKey:kIapUnverifyOrders] != nil) {
      [iapUnverifyOrdersArray addObjectsFromArray:[[NSUserDefaults standardUserDefaults] objectForKey:kIapUnverifyOrders]];
    }
    [iapUnverifyOrdersArray addObject:purchase];
    [[NSUserDefaults standardUserDefaults] setObject:[iapUnverifyOrdersArray copy] forKey:kIapUnverifyOrders];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    callback(@[[NSNull null], purchase]);
    [_callbacks removeObjectForKey:key];
  }
  
}

- (void)paymentQueue:(SKPaymentQueue *)queue
restoreCompletedTransactionsFailedWithError:(NSError *)error
{
  NSString *key = RCTKeyForInstance(@"restoreRequest");
  RCTResponseSenderBlock callback = _callbacks[key];
  if (callback) {
    callback(@[@"恢复购买失败"]);
    [_callbacks removeObjectForKey:key];
  } else {
    RCTLogWarn(@"No callback registered for restore product request.");
  }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
  NSString *key = RCTKeyForInstance(@"restoreRequest");
  RCTResponseSenderBlock callback = _callbacks[key];
  if (callback) {
    NSMutableArray *productsArrayForJS = [NSMutableArray array];
    for(SKPaymentTransaction *transaction in queue.transactions){
      if(transaction.transactionState == SKPaymentTransactionStateRestored) {
        [productsArrayForJS addObject:transaction.payment.productIdentifier];
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
      }
    }
    callback(@[[NSNull null], productsArrayForJS]);
    [_callbacks removeObjectForKey:key];
  } else {
    RCTLogWarn(@"No callback registered for restore product request.");
  }
}

// 所有可卖商品回调
- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
  NSString *key = RCTKeyForInstance(request);
  RCTResponseSenderBlock callback = _callbacks[key];
  if (callback) {
    products = [NSMutableArray arrayWithArray:response.products];
    NSMutableArray *productsArrayForJS = [NSMutableArray array];
    for(SKProduct *item in response.products) {
      NSDictionary *product = @{
                                @"identifier": item.productIdentifier,
                                @"priceString": item.priceString,
                                @"downloadable": item.downloadable ? @"true" : @"false" ,
                                @"description": item.localizedDescription ? item.localizedDescription : @"商品描述",
                                @"title": item.localizedTitle ? item.localizedTitle : @"商品名称",
                                };
      [productsArrayForJS addObject:product];
    }
    callback(@[[NSNull null], productsArrayForJS]);
    [_callbacks removeObjectForKey:key];
  } else {
    RCTLogWarn(@"No callback registered for load product request.");
  }
}

- (void)dealloc
{
  [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

#pragma mark Private

static NSString *RCTKeyForInstance(id instance)
{
  return [NSString stringWithFormat:@"%p", instance];
}
@end

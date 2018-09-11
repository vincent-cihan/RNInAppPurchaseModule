# RNInAppPurchaseModule
React-Native iOS内购模块，含缓存购买成功凭证防止丢单逻辑

RN内购GitHub上也有很多封装好的模块，不过基本上都是国外的，包含Google的Android iap，对国内来说不需要，而且也没有丢单的处理，于是根据自己需要封装了一个，就两个文件，没必要用npm了，直接拖到Xcode中使用。
简书地址：https://www.jianshu.com/p/71b3382455f1

### 一、调用API一览
```
// 1.获取与服务器交互验证失败，缓存下来的漏单数组
const iapUnverifyOrdersArray = RNInAppPurchaseModule.iapUnverifyOrdersArray;

// 2.注册iap，监听并处理因App意外退出产生的漏单
RNInAppPurchaseModule.addTransactionObserverWithCallback((error, purchase) => {
});

// 3.与服务器验证成功，删除缓存的凭证
RNInAppPurchaseModule.removePurchase(purchase);

// 4.与苹果服务器交互，加载可卖的内购商品
RNInAppPurchaseModule.loadProducts(iapProductIds, (error, products) => {
});

// 5.购买某个商品
RNInAppPurchaseModule.purchaseProduct(ProductId, (error, purchase) => {
});

// 6.恢复购买
RNInAppPurchaseModule.restorePurchases((error, products) => {
});
```

### 二、两种漏单内购情况
##### 1.App已经监听到苹果的购买成功回调，并且获得了内购凭证，再与服务器交互的过程中，验证失败（网络问题、或者服务器与苹果验证时产生问题）。这时需要缓存内购凭证，在适当的时候重新与服务器验证。
##### 2.用户购买过程中，App尚未接收到苹果购买成功回调，App意外闪退（没电、异常关机）。这时需要在App下次启动时，重新监听苹果购买回调并处理。

### 三、内购逻辑
以下是在我自己项目中的逻辑，可以根据自己项目需要调整：

##### 1.在App启动时，注册iap并检查有无漏单内购，如有，向服务器验证漏单内购
```
// 注册通知并检查漏单内购
async registAndCheckIap() {

// 处理与服务器交互失败，缓存下来的漏单
const iapUnverifyOrdersArray = RNInAppPurchaseModule.iapUnverifyOrdersArray;
for (let purchase of iapUnverifyOrdersArray) {
// TODO: 与服务器交互验证购买凭证
console.log(purchase);
......
// 验证成功，删除缓存的凭证
RNInAppPurchaseModule.removePurchase(purchase);
}

// 注册iap，监听并处理因App意外推出产生的漏单
RNInAppPurchaseModule.addTransactionObserverWithCallback((error, purchase) => {
// TODO: 与服务器交互验证购买凭证
console.log(purchase);
......
// 验证成功，删除缓存的凭证
RNInAppPurchaseModule.removePurchase(purchase);
});
}
```
##### 2.进入商品列表页面，请求所有可卖iap商品
```
// 加载iOS内购商品
if (iOS) {
RNInAppPurchaseModule.loadProducts(this.state.iapProductIds, (error, products) => {
});
}
```
##### 3.购买商品并验证
```
if (iOS) {

RNInAppPurchaseModule.purchaseProduct(produceId, (error, result) => {

if (error) {
BXAlert.showTipAlert('提示', error || '购买失败');
} else {
// TODO: 与服务器交互购买凭证
console.log(result);
......
// 验证成功，删除缓存的凭证
RNInAppPurchaseModule.removePurchase(result);
}
});
}
```





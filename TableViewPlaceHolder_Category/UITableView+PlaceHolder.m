//
//  UITableView+PlaceHolder.m
//  TableViewPlaceHolder_Category
//
//  Created by LSH on 2018/12/19.
//  Copyright © 2018 None. All rights reserved.
//

#import "UITableView+PlaceHolder.h"
#import <objc/runtime.h>
/*
 * 占位代理
 */


@protocol TableViewPlaceHolderDeleagte <NSObject>

@optional
- (UIView   *)placeHolder_noDataView;                //  完全自定义占位图
- (UIImage  *)placeHolder_noDataViewImage;           //  使用默认占位图, 提供一张图片,    可不提供, 默认不显示
- (NSString *)placeHolder_noDataViewMessage;         //  使用默认占位图, 提供显示文字,    可不提供, 默认为暂无数据
- (UIColor  *)placeHolder_noDataViewMessageColor;    //  使用默认占位图, 提供显示文字颜色, 可不提供, 默认为灰色
- (NSNumber *)placeHolder_noDataViewCenterYOffset;   //  使用默认占位图, CenterY 向下的偏移量

- (void)tapForReload;//点击刷新的方法
@end


@implementation UITableView (PlaceHolder)

+ (void)load
{
    //只交换一次
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method reloadData = class_getInstanceMethod(self, @selector(reloadData));
        Method placeHolder_reloadData = class_getInstanceMethod(self, @selector(placeHolder_reloadData));
        method_exchangeImplementations(reloadData, placeHolder_reloadData);

        Method dealloc = class_getInstanceMethod(self, NSSelectorFromString(@"dealloc"));
        Method placeHolder_dealloc = class_getInstanceMethod(self, @selector(placeHolder_dealloc));
        method_exchangeImplementations(dealloc, placeHolder_dealloc);
    });

}

- (void)placeHolder_reloadData
{
    [self placeHolder_reloadData];

    //  忽略第一次加载
    if (![self isInitFinish]) {
        [self placeHolder_havingData:YES netReach:YES];
        [self setIsInitFinish:YES];
        return ;
    }
    //  刷新完成之后检测数据量
    dispatch_async(dispatch_get_main_queue(), ^{

        NSInteger numberOfSections = [self numberOfSections];
        BOOL havingData = NO;
        for (NSInteger i = 0; i < numberOfSections; i++) {
            if ([self numberOfRowsInSection:i] > 0) {
                havingData = YES;
                break;
            }
        }
        [self placeHolder_havingData:havingData netReach:YES];
    });
}

/**
 展示占位图
 */
- (void)placeHolder_havingData:(BOOL)havingData netReach:(BOOL)hasNet{

    //  不需要显示占位图
    if (havingData) {
        [self freeNoDataViewIfNeeded];
        self.backgroundView = nil;
        return ;
    }

    //  不需要重复创建
    if (self.backgroundView) {
        return ;
    }

    //  自定义了占位图
    if ([self.delegate respondsToSelector:@selector(placeHolder_noDataView)]) {
        self.backgroundView = [self.delegate performSelector:@selector(placeHolder_noDataView)];
        return ;
    }

    //  使用自带的
    UIImage  *img   = [UIImage imageNamed:@"noData"];
    NSString *msg   = hasNet? @"暂无数据" : @"无网络";
    UIColor  *color = [UIColor lightGrayColor];
    CGFloat  offset = 0;

    //  获取图片
    if ([self.delegate    respondsToSelector:@selector(placeHolder_noDataViewImage)]) {
        img = [self.delegate performSelector:@selector(placeHolder_noDataViewImage)];
    }
    //  获取文字
    if ([self.delegate    respondsToSelector:@selector(placeHolder_noDataViewMessage)]) {
        msg = [self.delegate performSelector:@selector(placeHolder_noDataViewMessage)];
    }
    //  获取颜色
    if ([self.delegate      respondsToSelector:@selector(placeHolder_noDataViewMessageColor)]) {
        color = [self.delegate performSelector:@selector(placeHolder_noDataViewMessageColor)];
    }
    //  获取偏移量
    if ([self.delegate        respondsToSelector:@selector(placeHolder_noDataViewCenterYOffset)]) {
        offset = [[self.delegate performSelector:@selector(placeHolder_noDataViewCenterYOffset)] floatValue];
    }

    //  创建占位图
    self.backgroundView = [self placeHolder_defaultNoDataViewWithImage:img message:msg color:color offsetY:offset];
}


- (void)placeHolder_dealloc
{
    [self freeNoDataViewIfNeeded];
    [self placeHolder_dealloc];
}

/**
 默认的占位图
 */
- (UIView *)placeHolder_defaultNoDataViewWithImage:(UIImage *)image message:(NSString *)message color:(UIColor *)color offsetY:(CGFloat)offset {

    //  计算位置, 垂直居中, 图片默认中心偏上.
    CGFloat sW = self.bounds.size.width;
    CGFloat cX = sW / 2;
    CGFloat cY = self.bounds.size.height * (1 - 0.618) + offset;
    CGFloat iW = image.size.width;
    CGFloat iH = image.size.height;

    //  图片
    UIImageView *imgView = [[UIImageView alloc] init];
    imgView.frame        = CGRectMake(cX - iW / 2, cY - iH / 2, iW, iH);
    imgView.image        = image;

    //  文字
    UILabel *label       = [[UILabel alloc] init];
    label.font           = [UIFont systemFontOfSize:17];
    label.textColor      = [UIColor grayColor];
    label.text           = message;
    label.textAlignment  = NSTextAlignmentCenter;
    label.frame          = CGRectMake(0, CGRectGetMaxY(imgView.frame) + 24, sW, label.font.lineHeight);

    //  视图
    UIView *view   = [[UIView alloc] init];
    [view addSubview:imgView];
    [view addSubview:label];

    //  实现跟随 TableView 滚动
    [view addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];

    //    view.backgroundColor = [RedColor colorWithAlphaComponent:0.3];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapForReload:)];
    [view addGestureRecognizer:tap];
    return view;
}
/*
 *  监听
 */

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"frame"]) {
        /**
         在 TableView 滚动 ContentOffset 改变时, 会同步改变 backgroundView 的 frame.origin.y
         可以实现, backgroundView 位置相对于 TableView 不动, 但是我们希望
         backgroundView 跟随 TableView 的滚动而滚动, 只能强制设置 frame.origin.y 永远为 0
         兼容 MJRefresh
         */
        CGRect frame = [[change objectForKey:NSKeyValueChangeNewKey] CGRectValue];
        if (frame.origin.y != 0) {
            frame.origin.y  = 0;
            self.backgroundView.frame = frame;
        }
    }
}

#pragma mark 属性

/*
 *  是否加载完成数据的Setter ---Getter
 */
- (void)setIsInitFinish:(BOOL)finsih
{
    objc_setAssociatedObject(self, @selector(isInitFinish), @(finsih), OBJC_ASSOCIATION_ASSIGN);
}

- (BOOL)isInitFinish
{
   return objc_getAssociatedObject(self, _cmd);
}


/**
 移除 KVO 监听
 */
- (void)freeNoDataViewIfNeeded {

    [self.backgroundView removeObserver:self forKeyPath:@"frame" context:nil];
}




- (void)tapForReload:(UITapGestureRecognizer *)tap
{
    if ([self.delegate respondsToSelector:@selector(tapForReload)]) {
        [self.delegate performSelector:@selector(tapForReload)];
    }
}


@end

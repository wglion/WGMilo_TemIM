//
//  ChatViewModel.m
//  ComChat
//
//  Created by D404 on 15/6/6.
//  Copyright (c) 2015年 D404. All rights reserved.
//

#import "ChatViewModel.h"
#import <RACSubject.h>
#import "XMPPManager.h"
#import "NSDate+IM.h"
#import "Macros.h"
#import "ResourceManager.h"
#import <MBProgressHUD.h>
#import <ReactiveCocoa.h>
#import "UIViewAdditions.h"
#import <ASIHTTPRequest/ASIFormDataRequest.h>
#import "XMPPMessageArchiving_Message_CoreDataObject+ChatMessage.h"

#import <AFNetworking.h>


@interface ChatViewModel()<NSFetchedResultsControllerDelegate>

@property (nonatomic, strong) RACSignal *fetchLaterSignal;
@property (nonatomic, strong) RACSignal *fetchEarlierSignal;

@property (nonatomic, strong) NSFetchedResultsController *fetchedEarlierResultsController;
@property (nonatomic, strong) NSFetchedResultsController *fetchedLaterResultsController;

@property (nonatomic, strong) NSManagedObjectContext *model;
@property (nonatomic, strong) NSFetchRequest *fetchRequest;

@property (nonatomic, strong) NSDate *earlierDate;
@property (nonatomic, strong) NSDate *laterDate;
@property (nonatomic, assign) NSInteger newMessageCount;

@end



@implementation ChatViewModel


#pragma mark 初始化model
- (instancetype)initWithModel:(id)model
{
    if (self = [super init]) {
        self.model = model;
        
        self.fetchLaterSignal = [[RACSubject subject] setNameWithFormat:@"%@fetchLaterSignal", NSStringFromClass([ChatViewModel class])];
        
        self.fetchEarlierSignal = [[RACSubject subject] setNameWithFormat:@"%@fetchEarlierSignal", NSStringFromClass([ChatViewModel class])];
        self.totalResultsSectionArray = [NSMutableArray array];
        self.earlierResultsSectionArray = [NSMutableArray array];
        self.newMessageCount = 0;
    }
    return self;
}


#pragma mark 更新获取到的日期
- (void)updateFetchLaterDate
{
    NSLog(@"更新获取到的日期...");
    if (self.fetchedLaterResultsController.sections.count > 0) {
        id <NSFetchedResultsSectionInfo> sectionInfo = [self.fetchedLaterResultsController.sections lastObject];
        if (sectionInfo) {
            XMPPMessageArchiving_Message_CoreDataObject *laterMessage = [[sectionInfo objects] firstObject];
            if (laterMessage) {
                self.laterDate = laterMessage.timestamp;
            }
        }
    }
}

#pragma mark 合并获取到的结果
- (void)mergeAllFetchedResults
{
    NSLog(@"合并获取到的结果...");
    @synchronized(self) {
        [self.totalResultsSectionArray removeAllObjects];
        
        /* 合并最新聊天数组和历史聊天数组 */
        if (self.fetchedLaterResultsController.sections.count) {
            [self.totalResultsSectionArray addObjectsFromArray:self.fetchedLaterResultsController.sections];
        }
        if (self.earlierResultsSectionArray.count) {
            [self.totalResultsSectionArray addObjectsFromArray:self.earlierResultsSectionArray];
        }
    }
}

#pragma mark 返回全部消息数组
- (NSMutableArray *)totalResultsSectionArray
{
    @synchronized(self) {
        return _totalResultsSectionArray;
    }
}

#pragma mark 获取历史信息
- (void)fetchEarlierMessage
{
    NSLog(@"获取历史消息后，紧接着获取最新消息...");
    
    if (!self.earlierDate) {
        self.earlierDate = [NSDate date];
    }
    
    [self setPredicateForFetchEarlierMessage];
    
    NSError *error = nil;
    if (![self.fetchedEarlierResultsController performFetch:&error]) {
        NSLog(@"获取历史信息失败, %@", error);
    }
    else {
        NSIndexPath *indexPath = nil;
        NSArray *fetchedSections = self.fetchedEarlierResultsController.sections;
        if (fetchedSections.count > 0) {
            id <NSFetchedResultsSectionInfo> sectionInfo = [fetchedSections lastObject];
            if (sectionInfo) {
                XMPPMessageArchiving_Message_CoreDataObject *earlierMessage = [[sectionInfo objects] lastObject];
                if (earlierMessage) {
                    self.earlierDate = earlierMessage.timestamp;
                }
            }
            
            [self.earlierResultsSectionArray addObjectsFromArray:fetchedSections];
            
            // 合并当前聊天数组和历史数组
            [self mergeAllFetchedResults];
            
            sectionInfo = [fetchedSections firstObject];
            if ([sectionInfo numberOfObjects] > 0) {
                indexPath = [NSIndexPath indexPathForRow:[sectionInfo numberOfObjects] - 1 inSection:fetchedSections.count - 1];
            }
            [(RACSubject *)self.fetchEarlierSignal sendNext:indexPath];
        }
    }
    // 获取完历史消息，再获取最新消息，这样有新消息时，自动fetch
    [self fetchLaterMessage];
}

#pragma mark 获取最新信息
- (void)fetchLaterMessage
{
    if (!self.laterDate) {
        self.laterDate = [NSDate date];
    }
    
    [self setPredicateForFetchLaterMessage];
    
    NSError *error = nil;
    if (![self.fetchedLaterResultsController performFetch:&error]) {
        NSLog(@"获取最新消息失败, %@", error);
    }
    else {
        if (self.fetchedLaterResultsController.sections.count > 0) {
            [(RACSubject *)self.fetchLaterSignal sendNext:nil];
            
            //更新时间和查询条件
            [self updateFetchLaterDate];
            [self setPredicateForFetchLaterMessage];
        }
    }
}

#pragma mark 发送文本消息
- (void)sendMessageWithText:(NSString *)text
{
    if (text.length > 0) {
//        NSString *JSONString = [ChatMessageTextEntity JSONStringFromText:text];
        
#pragma mark - 这里先改成字符串的形式过去，没有编译成 json格式发送过去
        NSString *JSONString = text;
        [[XMPPManager sharedManager] sendChatMessage:JSONString
                                                 toJID:self.buddyJID];
    }
}

#pragma mark 图片压缩
- (UIImage *)imageWithImageSimple:(UIImage*)image scaledToSize:(CGSize)newSize
{
    newSize.height=image.size.height*(newSize.width/image.size.width);
    UIGraphicsBeginImageContext(newSize);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

#pragma mark 发送图片消息
- (void)sendMessageWithImage:(UIImage *)image
{
    NSLog(@"发送图片...");
    UIImage *newImage = image;
    if (image.size.width > 500.f || image.size.height > 500.f) {
        newImage = [self imageWithImageSimple:image scaledToSize:CGSizeMake(500, 500)];
    }
    NSData *imageData = UIImageJPEGRepresentation(newImage, 0.5);
    NSString *base64Str = [imageData base64EncodedStringWithOptions:0];
    
    NSLog(@"图片字符串***%@***",base64Str);
    
    //设置图片名称
    NSString *imageName = [ResourceManager generateImageTimeKeyWithPrefix:self.buddyJID.bare];
    
    //设置上传的路径
    NSString *url = @"http://121.40.202.227:8888/ykqapi/api/IMUpload/op/upload/json?SEESION_ID=0053B891AC3F702A811FC10C7E4D852E";
    //还有一个登录sessionId的参数，这个参数 可以在 这个url里进行拼接，或者 把他添加到请求头哪里去试一下。。。
    //SEESION_ID 一直在用就一直有效，如果不是，过了一定期限后（这里是一个小时），就要重新申请一下。。。
    
    NSMutableDictionary *PictureVO = [NSMutableDictionary dictionary];
    [PictureVO setObject:@"1" forKey:@"type"];
    [PictureVO setObject:imageName forKey:@"fileName"];
    [PictureVO setObject:base64Str forKey:@"fileDataStr"];
    NSArray *attachList = @[PictureVO];
    
    NSDictionary *params = @{@"attachList":attachList};
    
    AFHTTPRequestOperationManager *mgr = [AFHTTPRequestOperationManager manager];
    mgr.requestSerializer = [AFJSONRequestSerializer serializer];//这里设置成 请求的数据以json的格式进行请求，不设置的话，默认是 HTTP的格式进行请求的。。。
    mgr.responseSerializer = [AFHTTPResponseSerializer serializer];
    
    //post请求这里面的 params最终是放在请求体里面的。。。
    [mgr POST:url parameters:params success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        //<7b22666c 6167223a 31303031 2c226d73 67223a22 e682a8e6 b2a1e69c 89e799bb e5bd952c e8afb7e7 99bbe5bd 95227d> 16进制的格式：二进制的数据
        NSLog(@"success****");
        NSError *error = nil;
        NSDictionary *result = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:&error];
        NSLog(@"返回数据结果***%@***",result);
        
        [self sendMessageWithImageSuccess:result withNewImage:newImage];
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        
        NSLog(@"failer***%@***",error);
        
    }];
    
    //AFN post 还有一个post方法就是专门用来post上传图片的；
    
}
- (void)sendMessageWithImageSuccess:(id)responseObject withNewImage:(UIImage *)newImage
{
    if([[responseObject objectForKey:@"flag"] integerValue] == 100){
        
        NSArray *datas = [responseObject objectForKey:@"datas"];
        NSDictionary *resultDic = datas[0];
        NSString *path = [resultDic objectForKey:@"filePath"];
        NSString *JSONString = [ChatMessageImageEntity JSONStringWithImageWidth:newImage.size.width height:newImage.size.height url:path];
        [[XMPPManager sharedManager] sendChatMessage:JSONString toJID:self.buddyJID.bareJID];
    }else{
    
        UIAlertView *alertV = [[UIAlertView alloc] initWithTitle:@"提示" message:@"发送图片失败" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
        [alertV show];
    }
}


#pragma mark 采用BASE64编码发送语音
- (void)sendMessageWithData:(NSData *)data time:(NSString *)time
{
    NSLog(@"音频发送中...");
    NSString *base64Data = [data base64EncodedStringWithOptions:0];
    NSString *JSONString = [ChatMessageVoiceEntity JSONStringWithAudioData:base64Data time:time];
    [[XMPPManager sharedManager] sendChatMessage:JSONString toJID:self.buddyJID];
}


#pragma mark 发送音频消息:采用HTTP协议将语音以URL的方式存储在服务器，服务器转发URL给接受方。
- (void)sendMessageWithAudioTime:(NSInteger)time data:(NSData *)voiceData urlkey:(NSString *)voiceName
{
    NSLog(@"发送音频消息...");
    
    
    NSString *url = @"http://121.40.202.227:8888/ykqapi/api/IMUpload/op/upload/json?SEESION_ID=0053B891AC3F702A811FC10C7E4D852E";
    //还有一个登录sessionId的参数，这个参数 可以在 这个url里进行拼接，或者 把他添加到请求头哪里去试一下。。。
    
    NSString *voiceStr = [voiceData base64EncodedStringWithOptions:0];
    
    NSMutableDictionary *PictureVO = [NSMutableDictionary dictionary];
    [PictureVO setObject:@"2" forKey:@"type"];
    [PictureVO setObject:voiceName forKey:@"fileName"];
    [PictureVO setObject:voiceStr forKey:@"fileDataStr"];
    NSArray *attachList = @[PictureVO];
    
    NSDictionary *params = @{@"attachList":attachList};
    
    AFHTTPRequestOperationManager *mgr = [AFHTTPRequestOperationManager manager];
    mgr.requestSerializer = [AFJSONRequestSerializer serializer];
    mgr.responseSerializer = [AFHTTPResponseSerializer serializer];
    
    [mgr POST:url parameters:params success:^(AFHTTPRequestOperation *operation, id responseObject) {
        
        NSLog(@"success****");
        NSError *error = nil;
        NSDictionary *result = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:&error];
        NSLog(@"返回数据结果***%@***",result);
        
        [self sendMessageWithAudioTimeSuccess:result withTime:time];
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        
        NSLog(@"failer***%@***",error);
        
    }];

}
- (void)sendMessageWithAudioTimeSuccess:(id)response withTime:(NSInteger)time
{
    if([[response objectForKey:@"flag"] integerValue] == 100){
        
        NSArray *datas = [response objectForKey:@"datas"];
        NSDictionary *resultDic = datas[0];
        NSString *path = [resultDic objectForKey:@"filePath"];
        NSString *JSONString = [ChatMessageVoiceEntity JSONStringWithAudioTime:time url:path];
        [[XMPPManager sharedManager] sendChatMessage:JSONString toJID:self.buddyJID.bareJID];
    }else{
        
        UIAlertView *alertV = [[UIAlertView alloc] initWithTitle:@"提示" message:@"发送语音失败" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
        [alertV show];
    }

}


/////////////////////////////////////////////////////////////////////////////////
#pragma mark NSFetchedResultsController
/////////////////////////////////////////////////////////////////////////////////

#pragma mark 设置谓词获取更早信息
- (void)setPredicateForFetchEarlierMessage
{
    NSPredicate *filterPredicate1 = [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"bareJidStr = '%@'", self.buddyJID.bare]];
    NSPredicate *filterPredicate2 = [NSPredicate predicateWithFormat:@"%K < %@", @"timestamp", self.earlierDate];
    NSArray *subPredicates = [NSArray arrayWithObjects:filterPredicate1, filterPredicate2, nil];
    NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:subPredicates];
    [self.fetchedEarlierResultsController.fetchRequest setPredicate:predicate];
}

#pragma mark 设置谓词用于获取之后的信息
- (void)setPredicateForFetchLaterMessage
{
    NSPredicate *filterPredicate1 = [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"bareJidStr = '%@'", self.buddyJID.bare]];
    NSPredicate *filterPredicate2 = [NSPredicate predicateWithFormat:@"timestamp > %@", self.laterDate];
    NSArray *subPredicates = [NSArray arrayWithObjects:filterPredicate1, filterPredicate2, nil];
    NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:subPredicates];
    [self.fetchedLaterResultsController.fetchRequest setPredicate:predicate];
}

#pragma mark 获取历史消息
- (NSFetchedResultsController *)fetchedEarlierResultsController
{
    NSLog(@"获取历史消息NSFetched");
    if (_fetchedEarlierResultsController == nil) {
        NSManagedObjectContext *model = [[XMPPManager sharedManager] managedObjectContext_messageArchiving];
        
        NSEntityDescription *entity = [NSEntityDescription entityForName:@"XMPPMessageArchiving_Message_CoreDataObject" inManagedObjectContext:model];
        NSSortDescriptor *sd1 = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:NO];
        NSArray *sortDescriptors = [NSArray arrayWithObjects:sd1, nil];
        
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        [fetchRequest setEntity:entity];
        [fetchRequest setSortDescriptors:sortDescriptors];
        [fetchRequest setFetchLimit:10];
        
        _fetchedEarlierResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:model sectionNameKeyPath:@"sectionIdentifier" cacheName:nil];
    }
    return _fetchedEarlierResultsController;
}


#pragma mark 获取最新的消息
- (NSFetchedResultsController *)fetchedLaterResultsController
{
    NSLog(@"获取最新消息NSFetched");
    if (_fetchedLaterResultsController == nil) {
        NSManagedObjectContext *model = [[XMPPManager sharedManager] managedObjectContext_messageArchiving];
        
        NSEntityDescription *entity = [NSEntityDescription entityForName:@"XMPPMessageArchiving_Message_CoreDataObject" inManagedObjectContext:model];
        
        NSSortDescriptor *sd1 = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:NO];
        NSArray *sortDescriptors = [NSArray arrayWithObjects:sd1, nil];
        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
        [fetchRequest setEntity:entity];
        [fetchRequest setSortDescriptors:sortDescriptors];
        [fetchRequest setFetchLimit:10];
        
        _fetchedLaterResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:model sectionNameKeyPath:@"sectionIdentifier" cacheName:nil];
        
        [_fetchedLaterResultsController setDelegate:self];
    }
    return _fetchedLaterResultsController;
}

#pragma mark 内容变化
- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    [self mergeAllFetchedResults];
    [(RACSubject *)self.fetchLaterSignal sendNext:nil];
    [self updateFetchLaterDate];
    [self setPredicateForFetchLaterMessage];
}

#pragma mark 获取真实Section数目
- (NSInteger)getRealSection:(NSInteger)section
{
    return [self numberOfSections] - section - 1;
}


///////////////////////////////////////////////////////////////////
#pragma mark DataSource
///////////////////////////////////////////////////////////////////

#pragma mark section数目
- (NSInteger)numberOfSections
{
    return [self.totalResultsSectionArray count];
}

#pragma mark 每个消息的时间
- (NSString *)titleForHeaderInSection:(NSInteger)section
{
    id <NSFetchedResultsSectionInfo> theSection = [self.totalResultsSectionArray objectAtIndex:[self getRealSection:section]];
    NSString *dateString = [theSection name];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm"];
    NSDate *date = [formatter dateFromString:dateString];
    
    return [date formatChatMessageDate];
}


- (NSInteger)numberOfItemsInSection:(NSInteger)section
{
    id <NSFetchedResultsSectionInfo> sectionInfo = self.totalResultsSectionArray [[self getRealSection:section]];
    return [sectionInfo numberOfObjects];
}


- (XMPPMessageArchiving_Message_CoreDataObject *)objectAtIndexPath:(NSIndexPath *)indexPath
{
    id <NSFetchedResultsSectionInfo> sectionInfo = self.totalResultsSectionArray [[self getRealSection:indexPath.section]];
    NSInteger realRow = [sectionInfo numberOfObjects] - indexPath.row - 1;
    
    return [sectionInfo objects][realRow];
}


-(void)deleteObjectAtIndexPath:(NSIndexPath *)indexPath
{
    id <NSFetchedResultsSectionInfo> sectionInfo = self.totalResultsSectionArray[[self getRealSection:indexPath.section]];
    NSInteger realRow = [sectionInfo numberOfObjects] - indexPath.row - 1;// section 对应的object还是原数据
    NSManagedObject *object =  [sectionInfo objects][realRow];
    
    NSManagedObjectContext *context = [self.fetchedLaterResultsController managedObjectContext];
    if (object) {
        [context deleteObject:object];
        
        NSError *error = nil;
        if ([context save:&error] == NO) {
            NSLog(@"未解决的错误 %@, %@", error, [error userInfo]);
        }
    }
}



@end

//
//  QMChatDataSource.m
//  Pods
//
//  Created by Vitaliy Gurkovsky on 8/10/16.
//
//

#import "QMChatDataSource.h"

typedef NS_ENUM(NSInteger, QMDataSourceUpdateType) {
    QMDataSourceUpdateTypeAdd = 0,
    QMDataSourceUpdateTypeSet,
    QMDataSourceUpdateTypeUpdate,
    QMDataSourceUpdateTypeRemove
};

@interface QMChatDataSource()

@property (strong, nonatomic) NSMutableArray *messages;
@property (strong, nonatomic) NSMutableSet *dateDividers;
@property (nonatomic) dispatch_queue_t serialQueue;

@end

static NSComparator messageComparator = ^(QBChatMessage* obj1, QBChatMessage * obj2) {
    if ([obj1 isEqual:obj2]) {
        return (NSComparisonResult)NSOrderedSame;
    }
    else {
        NSCalendar *cal = [NSCalendar currentCalendar];
        
        NSCalendarUnit components = NSEraCalendarUnit | NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit | NSCalendarUnitHour|  NSCalendarUnitMinute;
        
        NSDateComponents *date1Components = [cal components:components fromDate:obj1.dateSent];
        NSDateComponents *date2Components = [cal components:components fromDate:obj2.dateSent];
        
        NSComparisonResult comparison = [[cal dateFromComponents:date2Components] compare:[cal dateFromComponents:date1Components]];
        if (comparison == NSOrderedSame) {
            return [obj2.ID compare:obj1.ID];
        }
        else {
            return comparison;
        }
    }
};


@implementation QMChatDataSource

#pragma mark -
#pragma mark Initialization

- (instancetype)init {
    
    self = [super init];
    
    if (self) {
        
        _dateDividers = [NSMutableSet set];
        _messages = [NSMutableArray array];
        _serialQueue = dispatch_queue_create("com.qmchatvc.datasource.queue", DISPATCH_QUEUE_SERIAL);
    }
    
    return self;
}

- (NSString *)description{
    return [NSString stringWithFormat:@"\n[QMDataSource] \n\t messages: %@", self.messages.copy];
}

#pragma mark -
#pragma mark Setting

- (void)setDataSourceMessages:(NSArray*)messages {
    [self changeDataSourceWithMessages:messages forUpdateType:QMDataSourceUpdateTypeSet];
}

#pragma mark -
#pragma mark Adding

- (void)addMessage:(QBChatMessage *)message {
    [self addMessages:@[message]];
}

- (void)addMessages:(NSArray<QBChatMessage *> *)messages {
    [self changeDataSourceWithMessages:messages forUpdateType:QMDataSourceUpdateTypeAdd];
}

#pragma mark -
#pragma mark Removing

- (void)deleteMessage:(QBChatMessage *)message  {
    [self deleteMessages:@[message]];
}

- (void)deleteMessages:(NSArray<QBChatMessage *> *)messages {
    [self changeDataSourceWithMessages:messages forUpdateType:QMDataSourceUpdateTypeRemove];
}

- (void)updateMessage:(QBChatMessage *)message {
    [self updateMessages:@[message]];
}

- (void)updateMessages:(NSArray<QBChatMessage *> *)messages {
    [self changeDataSourceWithMessages:messages forUpdateType:QMDataSourceUpdateTypeUpdate];
}

#pragma mark -
#pragma mark - Data Source

- (void)changeDataSourceWithMessages:(NSArray*)messages forUpdateType:(QMDataSourceUpdateType)updateType {
    
    dispatch_async(_serialQueue, ^{
        
        NSMutableArray *itemsIndexPaths = [NSMutableArray arrayWithCapacity:messages.count];
        
        for (QBChatMessage *message in messages) {
            
            NSAssert(message.dateSent != nil, @"Message must have dateSent!");
            
            if ([self shouldSkipMessage:message forDataSourceUpdateType:updateType]) {
                continue;
            }
            
            NSIndexPath *indexPath = [self indexPathForMessage:message];
            
            if (updateType == QMDataSourceUpdateTypeAdd
                || updateType == QMDataSourceUpdateTypeSet) {
                
                NSUInteger messageIndex = [self insertMessage:message];
                indexPath = [NSIndexPath indexPathForItem:messageIndex inSection:0];
            }
            
            else if (updateType == QMDataSourceUpdateTypeUpdate) {
                
                NSUInteger updatedMessageIndex = [self indexThatConformsToMessage:message];
                
                if (updatedMessageIndex != indexPath.item) {
                    // message will have new indexPath due to date changes
                    [self deleteMessages:@[message]];
                    [self addMessages:@[message]];
                }
                else {
                    [self.messages replaceObjectAtIndex:indexPath.item withObject:message];
                }
                
            }
            else if (updateType ==  QMDataSourceUpdateTypeRemove) {
                [self.messages removeObjectAtIndex:indexPath.item];
            }
            
            if (indexPath != nil) {
                [itemsIndexPaths addObject:indexPath];
            }
            
            [self handleMessage:message forUpdateType:updateType];
        }
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            
            if (itemsIndexPaths.count) {
                
                SEL selector = [self selectorForUpdateType:updateType];
                
                if ([self.delegate respondsToSelector:selector]) {
                    [self.delegate performSelector:selector withObject:itemsIndexPaths.copy];
                }
            }
        });
    });
}

- (BOOL)shouldSkipMessage:(QBChatMessage*)message forDataSourceUpdateType:(QMDataSourceUpdateType)updateType {
    
    BOOL messageExists = [self messageExists:message];
    
    if (updateType == QMDataSourceUpdateTypeAdd
        || updateType == QMDataSourceUpdateTypeSet) {
        
        return messageExists;
    }
    else if (updateType == QMDataSourceUpdateTypeUpdate
             || updateType == QMDataSourceUpdateTypeRemove) {
        return !messageExists;
    }
}


- (SEL)selectorForUpdateType:(QMDataSourceUpdateType)updateType {
    
    SEL selector = nil;
    
    switch (updateType) {
            
        case QMDataSourceUpdateTypeAdd: {
            selector = @selector(chatDataSource:didInsertMessagesAtIndexPaths:);
            break;
        }
        case QMDataSourceUpdateTypeSet: {
            selector = @selector(chatDataSource:didSetMessagesAtIndexPaths:);
            break;
        }
        case QMDataSourceUpdateTypeUpdate: {
            selector = @selector(chatDataSource:didUpdateMessagesAtIndexPaths:);
            break;
        }
        case QMDataSourceUpdateTypeRemove: {
            selector = @selector(chatDataSource:didDeleteMessagesAtIndexPaths:);
            break;
        }
    }
    
    return selector;
}

#pragma mark -
#pragma mark - Helpers

- (NSArray *)allMessages {
    
    return [self.messages copy];
}

- (NSInteger)messagesCount {
    
    return self.messages.count;
}

- (NSUInteger)insertMessage:(QBChatMessage *)message {
    
    NSUInteger index = [self indexThatConformsToMessage:message];
    [self.messages insertObject:message atIndex:index];
    
    return index;
}

- (QBChatMessage *)messageForIndexPath:(NSIndexPath *)indexPath {
    
    if (indexPath.item == NSNotFound) {
        return nil;
    }
    
    return self.messages[indexPath.item];
}


- (BOOL)messageExists:(QBChatMessage *)message {
    
    return [self.messages containsObject:message];
}

- (NSUInteger)indexThatConformsToMessage:(QBChatMessage *)message {
    
    NSArray * messagesArray = self.messages.copy;
    
    NSUInteger newIndex = [messagesArray indexOfObject:message
                                         inSortedRange:(NSRange){0,[messagesArray count]}
                                               options:(NSBinarySearchingFirstEqual | NSBinarySearchingInsertionIndex)
                                       usingComparator:messageComparator];
    
    return newIndex;
}

- (NSIndexPath *)indexPathForMessage:(QBChatMessage *)message {
    
    NSIndexPath *indexPath = nil;
    
    if ([self.messages containsObject:message]) {
        
        indexPath = [NSIndexPath indexPathForItem:[self.messages indexOfObject:message] inSection:0];
        
    }
    return indexPath;
}

- (BOOL)hasMessagesForDate:(NSDate*)messageDate {
    
    NSArray *uniqueDateTimes = [self.messages valueForKeyPath:@"@distinctUnionOfObjects.dateSent"];
    
    NSCalendar* calendar = [NSCalendar currentCalendar];
    
    NSDateComponents *dateComponents = [NSDateComponents new];
    dateComponents.day = 1;
    dateComponents.second = -1;
    
    NSDate * startDate = [calendar startOfDayForDate:messageDate];
    NSDate * endDate =  [calendar dateByAddingComponents:dateComponents
                                                  toDate:startDate
                                                 options:NSCalendarWrapComponents];
    
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(QBChatMessage*  _Nonnull message, NSDictionary<NSString *,id> * _Nullable bindings) {
        return !message.isDateDividerMessage &&
        [message.dateSent compare:startDate] == NSOrderedDescending &&
        [message.dateSent compare:endDate]  == NSOrderedAscending;
    }];
    
    NSArray * messages = [self.messages filteredArrayUsingPredicate:predicate];
    
    return messages.count > 0;
    
}

#pragma mark -
#pragma mark - Date Dividers

- (void)handleMessage:(QBChatMessage*)message forUpdateType:(QMDataSourceUpdateType)updateType {
    
    if (message.isDateDividerMessage) {
        return;
    }
    
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate * dateToAdd = [calendar startOfDayForDate:message.dateSent];
    
    if (updateType == QMDataSourceUpdateTypeAdd
        || updateType == QMDataSourceUpdateTypeSet) {
        
        if ([self.dateDividers containsObject:dateToAdd]) {
            return;
        }
        
        QBChatMessage * divideMessage = [QBChatMessage new];
        
        divideMessage.text = [self qm_stringFromDate:dateToAdd];
        divideMessage.dateSent = dateToAdd;
        
        divideMessage.isDateDividerMessage = YES;
        
        [self.dateDividers addObject:dateToAdd];
        
        [self changeDataSourceWithMessages:@[divideMessage] forUpdateType:updateType];
    }
    else {
        
        BOOL hasMessages = [self hasMessagesForDate:message.dateSent];
        
        if (hasMessages) {
            return;
        }
        
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(QBChatMessage*  _Nonnull message, NSDictionary<NSString *,id> * _Nullable bindings) {
            return message.isDateDividerMessage && [message.dateSent isEqualToDate:dateToAdd];
        }];
      
        QBChatMessage * msg = [[self.messages filteredArrayUsingPredicate:predicate] firstObject];
        [self deleteMessage:msg];
        [self.dateDividers removeObject:dateToAdd];

    }
}

- (NSString*)qm_stringFromDate:(NSDate*)date {
    
    NSCalendar *calendar = [NSCalendar currentCalendar];
    
    static NSDateFormatter* dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.locale = [NSLocale currentLocale];
        dateFormatter.timeZone = calendar.timeZone;
        [dateFormatter setDateFormat:@"d MMMM YYYY"];
    });

    return [dateFormatter stringFromDate:date];
}

@end

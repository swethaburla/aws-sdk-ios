/*
 * Copyright 2010-2012 Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 * You may not use this file except in compliance with the License.
 * A copy of the License is located at
 *
 *  http://aws.amazon.com/apache2.0
 *
 * or in the "license" file accompanying this file. This file is distributed
 * on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * permissions and limitations under the License.
 */

#import "S3MultipartUploadOperation.h"
#import "AmazonErrorHandler.h"

typedef void (^AbortMultipartUploadBlock)();

@interface S3MultipartUploadOperation ()
{
    BOOL _isExecuting;
    BOOL _isFinished;
}

@property (nonatomic, assign) NSUInteger contentLength;
@property (nonatomic, assign) NSUInteger currentPartNo;
@property (nonatomic, assign) NSInteger numberOfParts;
@property (nonatomic, assign) NSInteger retryCount;
@property (nonatomic, copy) AbortMultipartUploadBlock abortMultipartUpload;
@property (nonatomic, retain) S3InitiateMultipartUploadRequest *initRequest;
@property (nonatomic, retain) S3InitiateMultipartUploadResponse *initResponse;
@property (nonatomic, retain) S3MultipartUpload *multipartUpload;
@property (nonatomic, retain) S3CompleteMultipartUploadRequest *completeRequest;
@property (nonatomic, retain) NSData *dataForPart;

@end

@implementation S3MultipartUploadOperation

@synthesize delegate = _delegate;
@synthesize s3 = _s3;

@synthesize contentLength = _contentLength;
@synthesize currentPartNo = _currentPartNo;
@synthesize numberOfParts = _numberOfParts;
@synthesize retryCount = _retryCount;
@synthesize abortMultipartUpload = _abortMultipartUpload;
@synthesize initRequest = _initRequest;
@synthesize initResponse = _initResponse;
@synthesize multipartUpload = _multipartUpload;
@synthesize completeRequest = _completeRequest;
@synthesize dataForPart = _dataForPart;

#pragma mark - Class Lifecycle

- (id)init
{
    if (self = [super init])
    {
        _isExecuting = NO;
        _isFinished = NO;

        _contentLength = 0;
        _currentPartNo = 0;
        _numberOfParts = 0;
        _retryCount = 0;
    }

    return self;
}

- (void)dealloc
{
    [_s3 release];
    [_request release];
    [_response release];
    
    [_error release];
    [_exception release];
    
    [_abortMultipartUpload release];
    [_initRequest release];
    [_initResponse release];
    [_multipartUpload release];
    [_completeRequest release];
    [_dataForPart release];

    [super dealloc];
}

#pragma mark - Overwriding NSOperation Methods

- (void)start
{
    [self willChangeValueForKey:@"isExecuting"];
    _isExecuting = YES;
    [self didChangeValueForKey:@"isExecuting"];

    [self initiateUpload];
}

- (BOOL)isConcurrent
{
    return YES;
}

- (BOOL)isExecuting
{
    return _isExecuting;
}

- (BOOL)isFinished
{
    return _isFinished;
}

#pragma mark - Multipart Upload Methods

- (void)initiateUpload
{
    self.initRequest =
    [[[S3InitiateMultipartUploadRequest alloc] initWithKey:self.request.key
                                                  inBucket:self.request.bucket] autorelease];
    self.initRequest.cannedACL = self.request.cannedACL;
    self.initRequest.storageClass = self.request.storageClass;
    self.initRequest.serverSideEncryption = self.request.serverSideEncryption;
    self.initRequest.fullACL = self.request.fullACL;
    self.initRequest.authorization = self.request.authorization;
    self.initRequest.contentType = self.request.contentType;
    self.initRequest.securityToken = self.request.securityToken;
    self.initRequest.subResource = self.request.subResource;

    self.initRequest.cacheControl = self.request.cacheControl;
    self.initRequest.contentDisposition = self.request.contentDisposition;
    self.initRequest.contentEncoding = self.request.contentEncoding;
    self.initRequest.redirectLocation = self.request.redirectLocation;

    self.initRequest.delegate = self;

    self.retryCount = 0;
    self.response = nil;

    dispatch_sync(dispatch_get_main_queue(), ^{
        [self.s3 initiateMultipartUpload:self.initRequest];
    });
}

- (void)startUploadingParts
{
    self.completeRequest = [[[S3CompleteMultipartUploadRequest alloc] initWithMultipartUpload:self.multipartUpload] autorelease];
    self.completeRequest.delegate = self;

    self.abortMultipartUpload = ^{

        if(self.multipartUpload)
        {
            @try {
                S3AbortMultipartUploadRequest *abortRequest = [[S3AbortMultipartUploadRequest alloc] initWithMultipartUpload:self.multipartUpload];
                [self.s3 abortMultipartUpload:abortRequest];
            }
            @catch (NSException *exception) {

            }
        }

    };

    self.contentLength = [self contentLengthForRequest:self.request];
    self.numberOfParts = [self numberOfParts:self.contentLength];
    self.currentPartNo = 1;

    if(self.request.stream != nil)
    {
        [self.request.stream open];
    }

    self.retryCount = 0;
    [self uploadPart:self.currentPartNo];
}

- (void)uploadPart:(NSInteger)partNo
{
    NSRange dataRange = [self getDataRange:partNo withContentLength:self.contentLength];
    
    self.error = nil;
    self.exception = nil;

    if(self.retryCount > 0)
    {
        [self.s3 pauseExponentially:self.retryCount];
    }

    S3UploadPartRequest *uploadRequest = [[S3UploadPartRequest alloc] initWithMultipartUpload:self.multipartUpload];
    uploadRequest.partNumber = partNo;

    if(self.dataForPart == nil)
    {
        if(self.request.data != nil)
        {
            self.dataForPart = [self.request.data subdataWithRange:dataRange];
        }
        else
        {
            dispatch_sync(dispatch_get_main_queue(), ^{
                uint8_t buffer[self.partSize];
                NSUInteger readLength = 0;

                readLength = [self.request.stream read:buffer maxLength:self.partSize];
                self.dataForPart = [NSData dataWithBytes:buffer length:readLength];
            });
        }
    }

    uploadRequest.contentLength = self.dataForPart.length;
    uploadRequest.data = self.dataForPart;
    uploadRequest.delegate = self;

    self.response = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.s3 uploadPart:uploadRequest];
    });

    [uploadRequest release];
}

#pragma mark - AmazonServiceRequestDelegate Implementations

- (void)request:(AmazonServiceRequest *)request didCompleteWithResponse:(AmazonServiceResponse *)response
{
    if(!self.isFinished && self.isExecuting)
    {
        self.response = response;

        if([response isKindOfClass:[S3InitiateMultipartUploadResponse class]])
        {
            self.initResponse = (S3InitiateMultipartUploadResponse *)self.response;
            self.multipartUpload = self.initResponse.multipartUpload;

            dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            dispatch_async(queue, ^{

                [self startUploadingParts];
            });
        }
        else if([response isKindOfClass:[S3UploadPartResponse class]])
        {
            AMZLogDebug(@"UploadPart succeeded: %d", self.currentPartNo);
            
            S3UploadPartResponse *uploadPartResponse = (S3UploadPartResponse *)self.response;

            if(uploadPartResponse.etag == nil)
            {
                [self.s3 completeMultipartUpload:self.completeRequest];
            }
            else
            {
                [self.completeRequest addPartWithPartNumber:self.currentPartNo withETag:uploadPartResponse.etag];
                
                self.dataForPart = nil;
                self.retryCount = 0;

                if(self.currentPartNo < self.numberOfParts)
                {
                    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
                    dispatch_async(queue, ^{

                        self.currentPartNo++;
                        [self uploadPart:self.currentPartNo];
                    });
                }
                else
                {
                    if(self.request.stream)
                    {
                        [self.request.stream close];
                    }

                    [self.s3 completeMultipartUpload:self.completeRequest];
                }
            }
        }
        else if([response isKindOfClass:[S3CompleteMultipartUploadResponse class]])
        {
            if([self.delegate respondsToSelector:@selector(request:didCompleteWithResponse:)])
            {
                [self.delegate request:request
               didCompleteWithResponse:response];
            }

            [self finish];
        }
    }
}

- (void)request:(AmazonServiceRequest *)request didSendData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    if(!self.isFinished && self.isExecuting)
    {
        if([request isKindOfClass:[S3UploadPartRequest class]])
        {
            if([self.delegate respondsToSelector:@selector(request:didSendData:totalBytesWritten:totalBytesExpectedToWrite:)])
            {
                [self.delegate request:request
                           didSendData:bytesWritten
                     totalBytesWritten:(self.currentPartNo - 1) * self.partSize + totalBytesWritten
             totalBytesExpectedToWrite:self.contentLength];
            }
        }
    }
}

- (void)request:(AmazonServiceRequest *)request didFailWithError:(NSError *)error
{
    if(!self.isFinished && self.isExecuting)
    {
        AMZLogDebug(@"Error: %@", error);

        self.error = error;
        self.exception = [AmazonServiceException exceptionWithMessage:[error description] andError:error];

        if((self.s3.maxRetries > self.retryCount && (self.error || self.exception))
           && [self.s3 shouldRetry:nil exception:self.exception]
           && [self isExecuting])
        {
            AMZLogDebug(@"Retrying %@", [request class]);
            
            self.response = nil;
            self.retryCount++;
            
            if([request isKindOfClass:[S3InitiateMultipartUploadRequest class]])
            {
                [self.s3 initiateMultipartUpload:self.initRequest];
            }
            else if([request isKindOfClass:[S3UploadPartRequest class]])
            {
                dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
                dispatch_async(queue, ^{

                    [self uploadPart:self.currentPartNo];
                });
            }
            else if([request isKindOfClass:[S3CompleteMultipartUploadRequest class]])
            {
                [self.s3 completeMultipartUpload:self.completeRequest];
            }

            return;
        }

        if(self.abortMultipartUpload)
        {
            dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            dispatch_async(queue, self.abortMultipartUpload);
        }

        if([self.delegate respondsToSelector:@selector(request:didFailWithError:)])
        {
            [self.delegate request:request didFailWithError:error];
        }

        [self finish];
    }
}

- (void)request:(AmazonServiceRequest *)request didFailWithServiceException:(NSException *)exception
{
    if(!self.isFinished && self.isExecuting)
    {
        AMZLogDebug(@"Exception: %@", exception);

        self.exception = exception;

        if((self.s3.maxRetries > self.retryCount && (self.error || self.exception))
           && [self.s3 shouldRetry:nil exception:self.exception]
           && [self isExecuting])
        {
            AMZLogDebug(@"Retrying %@", [request class]);
            
            self.response = nil;
            self.retryCount++;
            
            if([request isKindOfClass:[S3InitiateMultipartUploadRequest class]])
            {
                [self.s3 initiateMultipartUpload:self.initRequest];
            }
            else if([request isKindOfClass:[S3UploadPartRequest class]])
            {
                dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
                dispatch_async(queue, ^{

                    [self uploadPart:self.currentPartNo];
                });
            }
            else if([request isKindOfClass:[S3CompleteMultipartUploadRequest class]])
            {
                [self.s3 completeMultipartUpload:self.completeRequest];
            }

            return;
        }

        if(self.abortMultipartUpload)
        {
            dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            dispatch_async(queue, self.abortMultipartUpload);
        }

        if([self.delegate respondsToSelector:@selector(request:didFailWithServiceException:)])
        {
            [self.delegate request:request didFailWithServiceException:exception];
        }

        [self finish];
    }
}

#pragma mark - Helper Methods

- (void)finish
{
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];

    _isExecuting = NO;
    _isFinished  = YES;

    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"isFinished"];
}

- (NSRange)getDataRange:(int)partNo withContentLength:(NSInteger)contentLength
{
    NSRange range;
    range.length = self.partSize;
    range.location = (partNo - 1) * self.partSize;

    int maxByte = partNo * self.partSize;
    if (contentLength < maxByte) {
        range.length = contentLength - range.location;
    }

    return range;
}

- (NSUInteger)contentLengthForRequest:(S3PutObjectRequest *)request
{
    if(request.data != nil)
    {
        return self.request.data.length;
    }
    else
    {
        return request.contentLength;
    }
}

- (NSUInteger)numberOfParts:(NSUInteger)contentLength
{
    return (NSUInteger)ceil((double)contentLength / self.partSize);
}

#pragma mark -

@end

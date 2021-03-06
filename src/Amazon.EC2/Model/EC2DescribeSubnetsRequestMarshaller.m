/*
 * Copyright 2010-2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
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

#import "EC2DescribeSubnetsRequestMarshaller.h"

@implementation EC2DescribeSubnetsRequestMarshaller

+(AmazonServiceRequest *)createRequest:(EC2DescribeSubnetsRequest *)describeSubnetsRequest
{
    AmazonServiceRequest *request = [[EC2Request alloc] init];

    [request setParameterValue:@"DescribeSubnets"           forKey:@"Action"];
    [request setParameterValue:@"2013-10-15"   forKey:@"Version"];

    [request setDelegate:[describeSubnetsRequest delegate]];
    [request setCredentials:[describeSubnetsRequest credentials]];
    [request setEndpoint:[describeSubnetsRequest requestEndpoint]];
    [request setRequestTag:[describeSubnetsRequest requestTag]];

    if (describeSubnetsRequest != nil) {
        if (describeSubnetsRequest.dryRunIsSet) {
            [request setParameterValue:(describeSubnetsRequest.dryRun ? @"true":@"false") forKey:[NSString stringWithFormat:@"%@", @"DryRun"]];
        }
    }

    if (describeSubnetsRequest != nil) {
        int subnetIdsListIndex = 1;
        for (NSString *subnetIdsListValue in describeSubnetsRequest.subnetIds) {
            if (subnetIdsListValue != nil) {
                [request setParameterValue:[NSString stringWithFormat:@"%@", subnetIdsListValue] forKey:[NSString stringWithFormat:@"%@.%d", @"SubnetId", subnetIdsListIndex]];
            }

            subnetIdsListIndex++;
        }
    }

    if (describeSubnetsRequest != nil) {
        int filtersListIndex = 1;
        for (EC2Filter *filtersListValue in describeSubnetsRequest.filters) {
            if (filtersListValue != nil) {
                if (filtersListValue.name != nil) {
                    [request setParameterValue:[NSString stringWithFormat:@"%@", filtersListValue.name] forKey:[NSString stringWithFormat:@"%@.%d.%@", @"Filter", filtersListIndex, @"Name"]];
                }
            }

            if (filtersListValue != nil) {
                int valuesListIndex = 1;
                for (NSString *valuesListValue in filtersListValue.values) {
                    if (valuesListValue != nil) {
                        [request setParameterValue:[NSString stringWithFormat:@"%@", valuesListValue] forKey:[NSString stringWithFormat:@"%@.%d.%@.%d", @"Filter", filtersListIndex, @"Value", valuesListIndex]];
                    }

                    valuesListIndex++;
                }
            }

            filtersListIndex++;
        }
    }


    return [request autorelease];
}

@end


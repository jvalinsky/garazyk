// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file NodeInfoSchemas.h

 @abstract NodeInfo schema constants and definitions.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! NodeInfo schema version 2.0 rel attribute. */
extern NSString *const NodeInfoSchemaRel20;

/*! NodeInfo schema version 2.1 rel attribute. */
extern NSString *const NodeInfoSchemaRel21;

/*! NodeInfo schema 2.0 profile URL. */
extern NSString *const NodeInfoSchemaProfile20;

/*! NodeInfo schema 2.1 profile URL. */
extern NSString *const NodeInfoSchemaProfile21;

/*! NodeInfo schema version string 2.0. */
extern NSString *const NodeInfoVersion20;

/*! NodeInfo schema version string 2.1. */
extern NSString *const NodeInfoVersion21;

/*! NodeInfo protocol name for ATProtocol. */
extern NSString *const NodeInfoProtocolAtproto;

/*! NodeInfo service name for no inbound services. */
extern NSString *const NodeInfoServiceEmptyInbound;

/*! NodeInfo service name for no outbound services. */
extern NSString *const NodeInfoServiceEmptyOutbound;

NS_ASSUME_NONNULL_END

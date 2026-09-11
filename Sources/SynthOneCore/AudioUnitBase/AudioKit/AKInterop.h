//  Replacement for AudioKit's AKInterop.h.
//
//  The AK_ENUM name is kept deliberately (ADR-009) so upstream headers — chiefly
//  S1Parameter.h with its 150 parameters — port with only their #import line changed.
//
//  FIX (P1-6): this shim originally spelled the Obj-C branch as NS_ENUM. That is
//  not what AudioKit 4.9.2 does, and it is not interchangeable. Upstream writes
//
//      typedef AK_ENUM(S1Parameter) { ... } S1Parameter;
//
//  which under NS_ENUM expands to a *variable* declaration after the closing
//  brace, colliding with the typedef name NS_ENUM forward-declares. It compiled
//  only because S1Parameter.h was reached from Obj-C++ translation units, where
//  the __cplusplus branch was taken. The moment the header goes public and the
//  Swift importer parses it as plain Obj-C, it is a hard error. Matching
//  AudioKit's real definition below also restores the Swift import that upstream
//  call sites assume: `S1Parameter.index1`, `S1Parameter(rawValue:)`.

#ifndef AK_INTEROP_H
#define AK_INTEROP_H

#import <Foundation/Foundation.h>

#ifdef __OBJC__
#define AK_ENUM(a) enum __attribute__((enum_extensibility(open))) a : int
#define AK_SWIFT_TYPE __attribute((swift_newtype(struct)))
#else
#define AK_ENUM(a) enum a
#define AK_SWIFT_TYPE
#endif

#endif /* AK_INTEROP_H */

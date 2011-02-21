//////////////////////////////////////////////////////////////////////
//
//  Copyright (c) 2006, Yusuke Miyao
//  You may distribute under the terms of the Artistic License.
//
//  Amis - A maximum entropy estimator
//
//  Author: Yusuke Miyao (yusuke@is.s.u-tokyo.ac.jp)
//  $Id$
//
//////////////////////////////////////////////////////////////////////
#include <zutil.h>
#include "GzStream.hpp"

static const int ASCII_FLAG  = 0x01;
static const int HEAD_CRC    = 0x02;
static const int EXTRA_FIELD = 0x04;
static const int ORIG_NAME   = 0x08;
static const int COMMENT     = 0x10;
static const int RESERVED    = 0xE0;

static const char gz_magic_number[] = { 0x1f, 0x8b };
static const char gz_header_string[] = { gz_magic_number[ 0 ], gz_magic_number[ 1 ], Z_DEFLATED, 0, 0, 0, 0, 0, 0, OS_CODE };

bool OGzStreamBuf::writeGzHeader() {
  out_stream.write( gz_header_string, sizeof( gz_header_string ) );
  return out_stream;
}

bool IGzStreamBuf::readGzHeader() {
  char buffer[10];
  in_stream.read( buffer, 10 );
  //std::cerr << "gcount=" << in_stream.gcount() << std::endl;
  //std::cerr << "buffer=" << buffer[0] << ' ' << buffer[1] << std::endl;
  //std::cerr << "magic=" << gz_magic_number[0] << ' ' << gz_magic_number[1] << std::endl;
  if ( in_stream.gcount() < 10 ) return false;
  if ( ! ( buffer[ 0 ] == gz_magic_number[ 0 ] &&
           buffer[ 1 ] == gz_magic_number[ 1 ] ) ) return false;
  if ( buffer[ 2 ] != Z_DEFLATED ) return false;
  int flag = buffer[ 3 ];
  //std::cerr << "flag=" << std::hex << flag << std::endl;
  if ( ( flag & EXTRA_FIELD ) != 0 ) {
    //std::cerr << "extra field" << std::endl;
    in_stream.read( buffer, 2 );
    if ( in_stream.gcount() < 2 ) return false;
    int len = buffer[ 0 ] + ( buffer[ 1 ] << 8 );
    //std::cerr << "len=" << len << std::endl;
    in_stream.ignore( len );
    if ( ! in_stream ) return false;
  }
  if ( ( flag & ORIG_NAME ) != 0 ) {
    //std::cerr << "orig name" << std::endl;
    while ( in_stream ) {
      //std::cerr << in_stream.peek() << std::endl;
      if ( in_stream.get() == '\0' ) break;
    }
    if ( ! in_stream ) return false;
  }
  if ( ( flag & COMMENT ) != 0 ) {
    //std::cerr << "comment" << std::endl;
    while ( in_stream ) {
      //std::cerr << in_stream.peek() << std::endl;
      if ( in_stream.get() == '\0' ) break;
    }
    if ( ! in_stream ) return false;
  }
  if ( ( flag & HEAD_CRC ) != 0 ) {
    //std::cerr << "head crc" << std::endl;
    in_stream.read( buffer, 2 );
    if ( in_stream.gcount() < 2 ) return false;
    if ( ! in_stream ) return false;
  }
  //std::cerr << "end" << std::endl;
  return true;
}

// end of GzStream.cc

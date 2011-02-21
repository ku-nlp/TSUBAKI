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

#ifndef GzStream_h_
#define GzStream_h_

#include <iostream>
#include <fstream>
#include <stdexcept>
#include <zlib.h>

typedef std::runtime_error ErrorBase;
/**
 * This class signals an error on gzstream
 */
class GzStreamError : public ErrorBase {
public:
  /// Initialize with an error message
  explicit GzStreamError( const std::string& s ) : ErrorBase( s ) {}
  /// Initialize with an error message
  explicit GzStreamError( const char* s ) : ErrorBase( s ) {}
  /// Destructor
  virtual ~GzStreamError() throw () {}
};

/**
 * error that zlib is not supported
 */
class GzStreamUnsupportedError : public ErrorBase {
public:
  /// Initialize with an error message
  explicit GzStreamUnsupportedError( const std::string& s ) : ErrorBase( s ) {}
  /// Initialize with an error message
  explicit GzStreamUnsupportedError( const char* s ) : ErrorBase( s ) {}
  /// Destructor
  virtual ~GzStreamUnsupportedError() throw () {}
};

/**
 * c++-stream-like interface for gzip.  Input stream.
 */

class IGzStreamBuf : public std::streambuf {
public:
  /// Type of size
  typedef size_t size_type;
  /// Type of data
  typedef char char_type;
  /// Default size of input buffer
  static const size_type DEFAULT_BUFFER_SIZE = 8192;

private:
  z_stream gz;
  std::istream& in_stream;
  size_type in_buffer_size;
  char_type* in_buffer;
  size_type out_buffer_size;
  char_type* out_buffer;
  bool is_initializing;

  uLong raw_length;
  uLong crc_checksum;

protected:
  /// Read a header of gz file
  bool readGzHeader();

public:
  /// Constructor
  explicit IGzStreamBuf( std::istream& is, size_type s = DEFAULT_BUFFER_SIZE )
    : in_stream( is ) {
    gz.next_in = Z_NULL;
    gz.avail_in = 0;
    gz.zalloc = Z_NULL;
    gz.zfree = Z_NULL;
    gz.opaque = Z_NULL;
    if ( inflateInit2( &gz, -MAX_WBITS ) != Z_OK ) {
      throw GzStreamError( "Initialization of zlib failed" );
    }
    in_buffer_size = s;
    in_buffer = new char_type[ in_buffer_size ];
    out_buffer_size = s;
    out_buffer = new char_type[ out_buffer_size ];
    is_initializing = true;

    crc_checksum = crc32(0L, Z_NULL, 0);
    raw_length = 0L;
  }
  /// Destructor
  virtual ~IGzStreamBuf() {
    delete [] out_buffer;
    delete [] in_buffer;
    if ( inflateEnd( &gz ) != Z_OK ) {
      throw GzStreamError( "Finalization of zlib failed" );
    }
  }

  bool checkSum()
  {
    unsigned char buf[8];

    for (size_t i = 0; i < 8; ++i) {
      if (gz.avail_in > 0) {
	buf[i] = (unsigned char) (*gz.next_in);
	--gz.avail_in;
	++gz.next_in;
      }
      else {
	int ret = in_stream.get();
	if (i == 7 && ret == EOF) {
	  return false;
	}
	buf[i] = ret;
      }
    }

    uLong crc_checksum_of_file = 0L;
    uLong raw_length_of_file = 0L;
    
    for (size_t i = 0; i < 4; ++i) {
      crc_checksum_of_file +=
	((unsigned long) buf[i]) << (8 * i);
      raw_length_of_file +=
	((unsigned long) buf[4+i]) << (8 * i);
    }

    bool crc_check = crc_checksum_of_file == (crc_checksum & 0xffffffff);
    bool length_check = raw_length_of_file == (raw_length & 0xffffffff);

    return crc_check && length_check;
  }

public:
  /// Called when out_buffer is empty
  int underflow() {
    if ( is_initializing ) {
      is_initializing = false;
      if ( ! readGzHeader() ) return EOF;
    }
    gz.next_out = reinterpret_cast< Bytef* >( out_buffer );
    gz.avail_out = out_buffer_size;
    while ( true ) {
      if ( gz.avail_in == 0 ) {
        in_stream.read( in_buffer, in_buffer_size );
        if ( in_stream.gcount() == 0 ) return EOF;
        //if ( ! in_stream ) return EOF;
        gz.next_in = reinterpret_cast< Bytef* >( in_buffer );
        gz.avail_in = in_stream.gcount();
      }
      int status = inflate( &gz, Z_NO_FLUSH );
      //std::cerr << status << std::endl;
      //std::cerr << gz.msg << std::endl;
      if ( status == Z_STREAM_END ) {
        if ( out_buffer_size == gz.avail_out ) {
          return EOF;
        }

	crc_checksum = crc32(crc_checksum, reinterpret_cast< Bytef* >(out_buffer), out_buffer_size - gz.avail_out);
	raw_length += out_buffer_size - gz.avail_out;
	if ( !checkSum() ) {
	  std::cerr << "GzStream: Wrong footer" << std::endl;
	}

        std::streambuf::setg( out_buffer, out_buffer, out_buffer + out_buffer_size - gz.avail_out );
        return *out_buffer;
      }
      if ( status != Z_OK ) throw GzStreamError( "Decompression by zlib failed" );
      if ( gz.avail_out == 0 ) {
	crc_checksum = crc32(crc_checksum, reinterpret_cast< Bytef* >(out_buffer), out_buffer_size);
	raw_length += out_buffer_size;
        std::streambuf::setg( out_buffer, out_buffer, out_buffer + out_buffer_size );
        return *out_buffer;
      }
    }
  }
};

//////////////////////////////////////////////////////////////////////

/**
 * c++-stream-like interface for gzip.  Output stream.
 */

class OGzStreamBuf : public std::streambuf {
public:
  /// Type of size
  typedef size_t size_type;
  /// Type of data
  typedef char char_type;
  /// Default size of input buffer
  static const size_type DEFAULT_BUFFER_SIZE = 8192;
  /// Default compression level (used by zlib)
  static const int DEFAULT_COMPRESSION = Z_DEFAULT_COMPRESSION;

private:
  z_stream gz;
  std::ostream& out_stream;
  size_type in_buffer_size;
  char_type* in_buffer;
  size_type out_buffer_size;
  char_type* out_buffer;
  bool is_initializing;

  uLong raw_length;
  uLong crc_checksum;

protected:
  /// Write a header of gz file
  bool writeGzHeader();

  /// Compress the data in the buffer
  bool compress() {
    if ( is_initializing ) {
      is_initializing = false;
      if ( ! writeGzHeader() ) return false;
    }
    gz.next_in = reinterpret_cast< Bytef* >( in_buffer );
    gz.avail_in = std::streambuf::pptr() - in_buffer;
    gz.next_out = reinterpret_cast< Bytef* >( out_buffer );
    gz.avail_out = out_buffer_size;

    crc_checksum = crc32(crc_checksum, gz.next_in, gz.avail_in);
    raw_length += gz.avail_in;
    while ( true ) {
      int status = deflate( &gz, Z_NO_FLUSH );
      if ( status != Z_OK ) throw GzStreamError( "Compression by zlib failed" );
      out_stream.write( out_buffer, out_buffer_size - gz.avail_out );
      //if ( ! out_stream ) return false;
      if ( gz.avail_in == 0 ) {
        setp( in_buffer, in_buffer + in_buffer_size );
        return true;
      }
      gz.next_out = reinterpret_cast< Bytef* >( out_buffer );
      gz.avail_out = out_buffer_size;
    }
  }

  /// Close the stream
  void finalize() {
    if ( is_initializing ) {
      is_initializing = false;
      if ( ! writeGzHeader() ) return;
    }
    int status = Z_OK;
    do {
      gz.next_out = reinterpret_cast< Bytef* >( out_buffer );
      gz.avail_out = out_buffer_size;
      status = deflate( &gz, Z_FINISH );
      if ( status != Z_OK && status != Z_STREAM_END ) throw GzStreamError( "Compression by zlib failed" );
      out_stream.write( out_buffer, out_buffer_size - gz.avail_out );
      //if ( ! out_stream ) return;
    } while ( status == Z_OK );


    writeLong(crc_checksum);
    writeLong(raw_length);
  }

private:
  void writeLong(uLong l)
  {
    for (size_t i = 0; i < 4; i++) {
      out_stream.put(static_cast<unsigned char>(l & 0xff));
      l >>= 8;
    }
  }

public:
  /// Constructor
  explicit OGzStreamBuf( std::ostream& os,
			 size_type s = DEFAULT_BUFFER_SIZE,
			 int comp_level = DEFAULT_COMPRESSION )
    : out_stream( os ) {
    gz.zalloc = Z_NULL;
    gz.zfree = Z_NULL;
    gz.opaque = Z_NULL;
    if ( deflateInit2( &gz, comp_level, Z_DEFLATED, -MAX_WBITS, MAX_MEM_LEVEL, Z_DEFAULT_STRATEGY ) != Z_OK ) {
      throw GzStreamError( "Initialization of zlib failed" );
    }
    in_buffer_size = s;
    in_buffer = new char_type[ in_buffer_size ];
    setp( in_buffer, in_buffer + in_buffer_size );
    out_buffer_size = s;
    out_buffer = new char_type[ out_buffer_size ];
    is_initializing = true;

    crc_checksum = crc32(0L, Z_NULL, 0);
    raw_length = 0L;
  }
  /// Destructor
  virtual ~OGzStreamBuf() {
    sync();
    finalize();
    delete [] out_buffer;
    delete [] in_buffer;
    if ( deflateEnd( &gz ) != Z_OK ) {
      throw GzStreamError( "Finalization of zlib failed" );
    }
  }

  /// Flush the output
  int sync() {
    if ( ! compress() ) return EOF;
    return 0;
  }

public:
  /// Called when out_buffer is empty
  int overflow( int c = EOF ) {
    if ( ! compress() ) return EOF;
    if ( c == EOF ) {
      finalize();
      return EOF;
    } else {
      *in_buffer = c;
      pbump( 1 );
    }
    return c;
  }
};

/**
 * Input stream for uncompressing
 */

class IGzStream : public std::istream {
private:
  IGzStreamBuf iz_buf;
public:
  /// Constructor with an input stream and buffer size
  explicit IGzStream( std::istream& is, size_t s = IGzStreamBuf::DEFAULT_BUFFER_SIZE )
    : std::istream( NULL ), iz_buf( is, s ) {
    init( &iz_buf );
  }
  /// Destructor
  virtual ~IGzStream() {
  }
};

/**
 * Input stream for compressed files
 */

class IGzFStream : public std::istream {
private:
  std::ifstream fs;
  IGzStreamBuf iz_buf;
public:
  /// Constructor with a file name and buffer size
  explicit IGzFStream( const std::string& name, size_t s = IGzStreamBuf::DEFAULT_BUFFER_SIZE )
    : std::istream( NULL ), fs( name.c_str() ), iz_buf( fs, s ) {
    init( &iz_buf );
  }
  /// Constructor with a file name and buffer size
  explicit IGzFStream( const char* name, size_t s = IGzStreamBuf::DEFAULT_BUFFER_SIZE )
    : std::istream( NULL ), fs( name ), iz_buf( fs, s ) {
    init( &iz_buf );
  }
  /// Destructor
  virtual ~IGzFStream() {
  }
};

/**
 * Output stream for compressing
 */

class OGzStream : public std::ostream {
private:
  OGzStreamBuf oz_buf;
public:
  /// Constructor with an output stream and buffer size
  explicit OGzStream( std::ostream& os, size_t s = OGzStreamBuf::DEFAULT_BUFFER_SIZE )
    : std::ostream( NULL ), oz_buf( os, s ) {
    init( &oz_buf );
  }
  // Destructor
  virtual ~OGzStream() {
  }
};

/**
 * Output stream for compressing files
 */

class OGzFStream : public std::ostream {
private:
  std::ofstream fs;
  OGzStreamBuf oz_buf;
public:
  /// Constructor with a file name and buffer size
  explicit OGzFStream( const std::string& name, size_t s = OGzStreamBuf::DEFAULT_BUFFER_SIZE )
    : std::ostream( NULL ), fs( name.c_str() ), oz_buf( fs, s ) {
    init( &oz_buf );
  }
  /// Constructor with a file name and buffer size
  explicit OGzFStream( const char* name, size_t s = OGzStreamBuf::DEFAULT_BUFFER_SIZE )
    : std::ostream( NULL ), fs( name ), oz_buf( fs, s ) {
    init( &oz_buf );
  }
  /// Destructor
  virtual ~OGzFStream() {
  }
};

#endif // GzStream_h_
// end of GzStream.h

/* Copyright (c) 2012 Scott Lembcke and Howling Moon Software
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/*
 * Code copied & pasted from SpacePatrol game https://github.com/slembcke/SpacePatrol
 *
 * Renamed and added some changes for cocos2d
 *
 */

#import "CCDrawNode.h"
#import "CCShaderCache.h"
#import "CCGLProgram.h"
#import "Support/CGPointExtension.h"


// ccVertex2F == CGPoint in 32-bits, but not in 64-bits (OS X)
// that's why the "v2f" functions are needed
static ccVertex2F v2fzero = (ccVertex2F){0,0};

static inline ccVertex2F v2f( float x, float y )
{
	return (ccVertex2F){x,y};
}

static inline ccVertex2F v2fadd( ccVertex2F v0, ccVertex2F v1 )
{
	return v2f( v0.x+v1.x, v0.y+v1.y );
}

static inline ccVertex2F v2fsub( ccVertex2F v0, ccVertex2F v1 )
{
	return v2f( v0.x-v1.x, v0.y-v1.y );
}

static inline ccVertex2F v2fmult( ccVertex2F v, float s )
{
	return v2f( v.x * s, v.y * s );
}

static inline ccVertex2F v2fperp( ccVertex2F p0 )
{
	return v2f( -p0.y, p0.x );
}

static inline ccVertex2F v2fneg( ccVertex2F p0 )
{
	return v2f( -p0.x, - p0.y );
}

static inline float v2fdot(ccVertex2F p0, ccVertex2F p1)
{
	return  p0.x * p1.x + p0.y * p1.y;
}

static inline ccVertex2F v2fforangle( float _a_)
{
	return v2f( cosf(_a_), sinf(_a_) );
}

static inline ccVertex2F v2fnormalize( ccVertex2F p )
{
	CGPoint r = ccpNormalize( ccp(p.x, p.y) );
	return v2f( r.x, r.y);
}

static inline ccVertex2F __v2f(CGPoint v )
{
#ifdef __LP64__
	return v2f(v.x, v.y);
#else
	return * ((ccVertex2F*) &v);
#endif
}



//#define PRINT_GL_ERRORS() for(GLenum err = glGetError(); err; err = glGetError()) NSLog(@"GLError(%s:%d) 0x%04X", __FILE__, __LINE__, err);
#define PRINT_GL_ERRORS() 

typedef struct Vertex {ccVertex2F vertex, texcoord; ccColor4B color;} Vertex;
typedef struct Triangle {Vertex a, b, c;} Triangle;

@interface CCDrawNode(){
	GLuint _vao;
	GLuint _vbo;
	
	NSUInteger _bufferCapacity, _bufferCount;
	Vertex *_buffer;
}

@end


@implementation CCDrawNode

@synthesize blendFunc = _blendFunc;

#pragma mark memory

-(void)ensureCapacity:(NSUInteger)count
{
	if(_bufferCount + count > _bufferCapacity){
		_bufferCapacity += MAX(_bufferCapacity, count);
		_buffer = realloc(_buffer, _bufferCapacity*sizeof(Vertex));
		
//		NSLog(@"Resized vertex buffer to %d", _bufferCapacity);
	}
}

-(id)init
{
	if((self = [super init])){
		self.blendFunc = (ccBlendFunc){GL_ONE, GL_ONE_MINUS_SRC_ALPHA};
		
		self.shaderProgram = [[CCShaderCache sharedShaderCache] programForKey:kCCShader_PositionLengthTexureColor];
		
		glGenVertexArrays(1, &_vao);
		glBindVertexArray(_vao);
			
		glGenBuffers(1, &_vbo);
		glBindBuffer(GL_ARRAY_BUFFER, _vbo);
		[self ensureCapacity:512];
    
		glEnableVertexAttribArray(kCCVertexAttrib_Position);
		glVertexAttribPointer(kCCVertexAttrib_Position, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid *)offsetof(Vertex, vertex));
		
		glEnableVertexAttribArray(kCCVertexAttrib_TexCoords);
		glVertexAttribPointer(kCCVertexAttrib_TexCoords, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (GLvoid *)offsetof(Vertex, texcoord));
		
		glEnableVertexAttribArray(kCCVertexAttrib_Color);
		glVertexAttribPointer(kCCVertexAttrib_Color, 4, GL_UNSIGNED_BYTE, GL_TRUE, sizeof(Vertex), (GLvoid *)offsetof(Vertex, color));
    
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		glBindVertexArray(0);
		PRINT_GL_ERRORS();
		
		_dirty = NO;
	}
	
	return self;
}

-(void)dealloc
{
#ifdef __CC_PLATFORM_IOS
	NSAssert([EAGLContext currentContext], @"No GL context set!");
#endif
	
	free(_buffer); _buffer = 0;
	
	glDeleteBuffers(1, &_vbo); _vbo = 0;
	glDeleteVertexArrays(1, &_vao); _vao = 0;
	
	[super dealloc];
}

#pragma mark Rendering

-(void)render
{
	if( _dirty ) {
		glBindBuffer(GL_ARRAY_BUFFER, _vbo);
		glBufferData(GL_ARRAY_BUFFER, sizeof(Vertex)*_bufferCapacity, _buffer, GL_STREAM_DRAW);
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		_dirty = NO;
	}
	
	ccGLBindVAO(_vao);
	glDrawArrays(GL_TRIANGLES, 0, _bufferCount);
	
	CC_INCREMENT_GL_DRAWS(1);
	
	PRINT_GL_ERRORS();
}

-(void)draw
{
	ccGLBlendFunc(_blendFunc.src, _blendFunc.dst);
	
	[shaderProgram_ use];
	[shaderProgram_ setUniformsForBuiltins];
	
	[self render];	
}

#pragma mark Immediate Mode

-(void)drawDot:(CGPoint)pos radius:(CGFloat)radius color:(ccColor4F)color;
{
	NSUInteger vertex_count = 2*3;
	[self ensureCapacity:vertex_count];
	
	Vertex a = {{pos.x - radius, pos.y - radius}, {-1.0, -1.0}, ccc4BFromccc4F(color) };
	Vertex b = {{pos.x - radius, pos.y + radius}, {-1.0,  1.0}, ccc4BFromccc4F(color) };
	Vertex c = {{pos.x + radius, pos.y + radius}, { 1.0,  1.0}, ccc4BFromccc4F(color) };
	Vertex d = {{pos.x + radius, pos.y - radius}, { 1.0, -1.0}, ccc4BFromccc4F(color) };
	
	Triangle *triangles = (Triangle *)(_buffer + _bufferCount);
	triangles[0] = (Triangle){a, b, c};
	triangles[1] = (Triangle){a, c, d};
	
	_bufferCount += vertex_count;
	
	_dirty = YES;
}

-(void)drawSegmentFrom:(CGPoint)_a to:(CGPoint)_b radius:(CGFloat)radius color:(ccColor4F)color;
{
	NSUInteger vertex_count = 6*3;
	[self ensureCapacity:vertex_count];
	
	ccVertex2F a = __v2f(_a);
	ccVertex2F b = __v2f(_b);
	
	
	ccVertex2F n = v2fnormalize(v2fperp(v2fsub(b, a)));
	ccVertex2F t = v2fperp(n);
	
	ccVertex2F nw = v2fmult(n, radius);
	ccVertex2F tw = v2fmult(t, radius);
	ccVertex2F v0 = v2fsub(b, v2fadd(nw, tw));
	ccVertex2F v1 = v2fadd(b, v2fsub(nw, tw));
	ccVertex2F v2 = v2fsub(b, nw);
	ccVertex2F v3 = v2fadd(b, nw);
	ccVertex2F v4 = v2fsub(a, nw);
	ccVertex2F v5 = v2fadd(a, nw);
	ccVertex2F v6 = v2fsub(a, v2fsub(nw, tw));
	ccVertex2F v7 = v2fadd(a, v2fadd(nw, tw));
	
	
	Triangle *triangles = (Triangle *)(_buffer + _bufferCount);
	triangles[0] = (Triangle){{v0, v2fneg(v2fadd(n, t)), ccc4BFromccc4F(color) }, {v1, v2fsub(n, t), ccc4BFromccc4F(color) }, {v2, v2fneg(n), ccc4BFromccc4F(color)},};
	triangles[1] = (Triangle){{v3, n, ccc4BFromccc4F(color)}, {v1, v2fsub(n, t), ccc4BFromccc4F(color)}, {v2, v2fneg(n), ccc4BFromccc4F(color) },};
	triangles[2] = (Triangle){{v3, n, ccc4BFromccc4F(color)}, {v4, v2fneg(n), ccc4BFromccc4F(color)}, {v2, v2fneg(n), ccc4BFromccc4F(color)},};
	triangles[3] = (Triangle){{v3, n, ccc4BFromccc4F(color)}, {v4, v2fneg(n), ccc4BFromccc4F(color)}, {v5, n, ccc4BFromccc4F(color)},};
	triangles[4] = (Triangle){{v6, v2fsub(t, n), ccc4BFromccc4F(color)}, {v4, v2fneg(n), ccc4BFromccc4F(color)}, {v5, n, ccc4BFromccc4F(color)},};
	triangles[5] = (Triangle){{v6, v2fsub(t, n), ccc4BFromccc4F(color)}, {v7, v2fadd(n, t), ccc4BFromccc4F(color)}, {v5, n, ccc4BFromccc4F(color)},};
	
	_bufferCount += vertex_count;
	
	_dirty = YES;
}

-(void)drawPolyWithVerts:(CGPoint *)verts count:(NSUInteger)count fillColor:(ccColor4F)fill  borderWidth:(CGFloat)width borderColor:(ccColor4F)line;
{
	struct ExtrudeVerts {ccVertex2F offset, n;};
	struct ExtrudeVerts extrude[count];
	bzero(extrude, sizeof(extrude) );
	
	for(int i=0; i<count; i++){
		ccVertex2F v0 = __v2f( verts[(i-1+count)%count] );
		ccVertex2F v1 = __v2f( verts[i] );
		ccVertex2F v2 = __v2f( verts[(i+1)%count] );
	
		ccVertex2F n1 = v2fnormalize(v2fperp(v2fsub(v1, v0)));
		ccVertex2F n2 = v2fnormalize(v2fperp(v2fsub(v2, v1)));
		
		ccVertex2F offset = v2fmult(v2fadd(n1, n2), 1.0/(v2fdot(n1, n2) + 1.0));
		extrude[i] = (struct ExtrudeVerts){offset, n2};
	}
	
	BOOL outline = (line.a > 0.0 && width > 0.0);
	
	NSUInteger triangle_count = 3*count - 2;
	NSUInteger vertex_count = 3*triangle_count;
	[self ensureCapacity:vertex_count];
	
	Triangle *triangles = (Triangle *)(_buffer + _bufferCount);
	Triangle *cursor = triangles;
	
	CGFloat inset = (outline == 0.0 ? 0.5 : 0.0);
	for(int i=0; i<count-2; i++){
		ccVertex2F v0 = v2fsub( __v2f(verts[0  ]), v2fmult(extrude[0  ].offset, inset));
		ccVertex2F v1 = v2fsub( __v2f(verts[i+1]), v2fmult(extrude[i+1].offset, inset));
		ccVertex2F v2 = v2fsub( __v2f(verts[i+2]), v2fmult(extrude[i+2].offset, inset));
		
		*cursor++ = (Triangle){{v0, v2fzero, ccc4BFromccc4F(fill)}, {v1, v2fzero, ccc4BFromccc4F(fill)}, {v2, v2fzero, ccc4BFromccc4F(fill)},};
	}
	
	for(int i=0; i<count; i++){
		int j = (i+1)%count;
		ccVertex2F v0 = __v2f( verts[i] );
		ccVertex2F v1 = __v2f( verts[j] );
		
		ccVertex2F n0 = extrude[i].n;
		
		ccVertex2F offset0 = extrude[i].offset;
		ccVertex2F offset1 = extrude[j].offset;
		
		if(outline){
			ccVertex2F inner0 = v2fsub(v0, v2fmult(offset0, width));
			ccVertex2F inner1 = v2fsub(v1, v2fmult(offset1, width));
			ccVertex2F outer0 = v2fadd(v0, v2fmult(offset0, width));
			ccVertex2F outer1 = v2fadd(v1, v2fmult(offset1, width));
			
			*cursor++ = (Triangle){{inner0, v2fneg(n0), ccc4BFromccc4F(line)}, {inner1, v2fneg(n0), ccc4BFromccc4F(line)}, {outer1, n0, ccc4BFromccc4F(line)}};
			*cursor++ = (Triangle){{inner0, v2fneg(n0), ccc4BFromccc4F(line)}, {outer0, n0, ccc4BFromccc4F(line)}, {outer1, n0, ccc4BFromccc4F(line) }};
		} else {
			ccVertex2F inner0 = v2fsub(v0, v2fmult(offset0, 0.5));
			ccVertex2F inner1 = v2fsub(v1, v2fmult(offset1, 0.5));
			ccVertex2F outer0 = v2fadd(v0, v2fmult(offset0, 0.5));
			ccVertex2F outer1 = v2fadd(v1, v2fmult(offset1, 0.5));
			
			*cursor++ = (Triangle){{inner0, v2fzero, ccc4BFromccc4F(fill)}, {inner1, v2fzero, ccc4BFromccc4F(fill)}, {outer1, n0, ccc4BFromccc4F(fill)}};
			*cursor++ = (Triangle){{inner0, v2fzero, ccc4BFromccc4F(fill)}, {outer0, n0, ccc4BFromccc4F(fill)}, {outer1, n0, ccc4BFromccc4F(fill)}};
		}
	}
	
	_bufferCount += vertex_count;
	
	_dirty = YES;
}

-(void)clear
{
	_bufferCount = 0;
}

@end

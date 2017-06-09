BasicUpstart2(begin)      // <- This creates a basic sys line that can start your program

//*************************************************
//* Sinus animation in Bitplain                   *
//*************************************************

// Vars
xpix:    .word $0000   // X position to draw the pixel to
ypix:    .byte $00     // Y position to draw the pixel to
anoff:   .byte $00     // Animation offset
piroffx:  .byte $00			// Period offset
piroffy:  .byte $22			// Period offset
pixrm:   .fill 100, 0  // List of bytes to remove
pixcn:   .byte 0			  // Array counter

// Zero page

// C64 memory map
.const SCRCONTREG    = $D011 // Screen control register
.const CURRASTLN     = $D012
.const MEMSETREG     = $D018 // VIC II memory map control
.const INTSTATREG    = $D019
.const INTVICCONTREG = $D01A
.const INTCONTREG1   = $DC0D // CIA 1 Interrupt control
.const INTCONTREG2   = $DD0D // CIA 2 Interrupt control
.const INTVEC        = $FFFE

.pc = $9000 "Data"
.align $40

// Sinus lookup table
.var i=0
.var len=256
sintab:
.while (i++<len) {
  .var x = round(100-(90*sin((i*2*PI)/(len))))
  .print "" + i + " value: " + x
  .byte x 
}

// 8 value mask table
bitmask:
.for(var count=0; count<8; count++){
  .byte (128>>count)
  .print (128>>count)
}

// Screen memory Y axis lookup table
.pc = $9200 "Yoffset table"
yoffset:
.var countloop=0
.for(var base=$2000; base<$3FFF; base=base+$140) {
  .for(var offset=0; offset<8; offset++) {
    .word (base+offset)
  //  .print "" + (countloop) + ":"  + (base+offset-8192) + " : " + (base+offset)
  //  .eval countloop = countloop+2
  }
}

// Start of the main program
* = $8000 "Main Program"    // <- The name 'Main program' will appear in the memory map when assembling   jsr clear
begin:

  //
  // Disable interrupts and start initialization
  sei                  // Disable interrupts

  lda #%01111111       // Disable CIA IRQ's
  sta INTCONTREG1      // Clear interrupt register1
  sta INTCONTREG2      // Clear interrupt register2

  lda #$35             // Bank out kernal and basic
  sta $01              // $e000-$ffff
  
  //
  // Border and frame both black
  lda #$0
  sta $D020
  sta $D021


  //
  // Clear character memory
  ldx #$00
!clear:  
  lda #$10     // set foreground to black in Color Ram 
  sta $0400,x  // fill four areas with 256 spacebar characters
  sta $0500,x
  sta $0600,x 
  sta $06e8,x 
  inx           // increment X
  bne !clear-   // did X turn to zero yet?
  
  lda SCRCONTREG       // Put the VIC into bitmap graphics mode
  ora #%00100000       // Enable bitmap mode bit 6
  sta SCRCONTREG

  lda MEMSETREG        // Remap the graphirs memory to $2000-$3FFF
  ora #%00001000
  sta MEMSETREG

	// Clear the bitmap
	jsr clearbitmap

	// Setup the raster interrupt
	jsr raster_init

  // Start teh main routine
  asl INTSTATREG				// Ack any previous raster interrupt
  bit $dc0d							// reading the interrupt control registers 
  bit $dd0d							// clears them
	cli										// Enable interrupts again


//////
//// Bar on the right of the screen
//  ldx #0
//!loop:
//  lda copy1:$9200, x   // load the lower byte into A
//  sta dispaddr1    // store it in the display address
//
//  lda copy2:$9200+1, x   // load the upper byte into A
//  sta dispaddr1+1  // store it in the display address
//  inx              // to next word
//  inx              // to next byte
//
//  bne !+           // Trigger on 255 -> 0 (256)
//  inc copy1+1    // DEBUG destructive, but good enough for now  
//  inc copy2+1    // DEBUG destructive, but good enough for now  
//!:
//
//  lda #$55         // All bytes to one to display
//  sta dispaddr1:$FFFF   // set the bytes
//  lda dispaddr1+1  // Did we reach $3fff yet?
//  cmp $3F
//  bne !loop-



////
// Ad infinum
  jmp *

  rts 

////
// Raster interrupt routine
irq1:
// save registers
  pha
  txa
  pha
  tya
  pha

// Debug
	lda #1								// To White
	sta $d020

  lda #$ff							// Acknowledge interrupt
  sta	$d019

// Clear the last run
	jsr clearpixels

// Debug
	lda #2								// To brown
	sta $d020

// Draw some pixels
	lda #$00
	sta xpix + 1

	lda #$07						// Mask lower 3 bits, to animate 0-7
	and anoff					  // Pixel offset
	inc anoff
	ldx #$00
	inc piroffx					// change period
	inc piroffy					// change period
	inc piroffy					// change period
!:
	pha
	adc piroffy					// Y progression
	tay
	lda sintab,y				// Sinus X lookup
	sta xpix						// Set X draw coordinate

	pla
	pha									// Store the counter
	
	adc piroffx					// period offset sinus wave X
	tay									// Lookup Y from sinus table
	lda sintab,	y
	sta ypix

	txa									// Store the X register
	pha

	jsr drawpixel				// Draw the pixel that 

	pla									// Restore the X
	tax
	pla									// Restore A

	clc
	adc #$10
	inx
	cpx #$10
	bne !-

  // Trigger at raster line 200
  ldy #240
  sty $d012

	// Debug
	lda #0
	sta $d020

	// Restore registers
  pla
  tay
  pla
  tax
  pla

	rti

  
////
// Initialize Raster interrupt
raster_init: 
  lda #$3b //Clear the High bit (lines 256-318)
  sta SCRCONTREG

  lda #$F8
  sta CURRASTLN

  lda #<irq1
  sta INTVEC
  lda #>irq1
  sta INTVEC+1
  lda #%00000001
  sta INTSTATREG
  sta INTVICCONTREG
  rts


//// 
// Write a pixel
// Store 
// X in xpix word
// Y in ypix byte
// touches : X, A, carry
drawpixel:
	// Reset self modifying code
	lda #$00
	sta drawaddr
	sta drawyofflo
	sta drawyoffhi
	lda #$20
	sta drawaddr+1
	lda #$92
	sta drawyofflo+1
	sta drawyoffhi+1

	// Get Y offset
	clc
	lda ypix							// ypix offset times 2
	rol 
	sta drawyofflo
	sta drawyoffhi

	bcc !+								// If an overflow occurs, add one to the msb
	inc drawyofflo+1
	inc drawyoffhi+1
!:

	lda drawyofflo:$FFFF    // Get lower y offset address	
	sta drawaddr	

	clc
	ldx #$01
	lda drawyoffhi:$FFFF, x // Get the higher offset address
	sta drawaddr+1

	// Get the X offset and add it to the drawaddr
	lda #%11111000					// calculate the lsb offset
	and xpix								
	
	clc											// Store in the drawaddr lsb
	adc drawaddr
	sta drawaddr

	lda xpix+1							// Get the X msb, add it to the drawaddr msb + carry
	adc drawaddr+1
	sta drawaddr+1				

	// Or mask byte
	lda #%00000111
	and xpix
	tax
	lda bitmask, x					// get the correct bitmask 

	sta drawaddr:$FFFF			// Just put the pixel clearing the other 7 pixels *LAZY*

	// store the location in the erase arrey
	ldx pixcn								// Get the pixel counter
	lda drawaddr						// Get the draw addr low byte
	sta pixrm, x						// Store low byte
	inx
	lda drawaddr+1					// High byte
	sta pixrm, x
	inx
	stx pixcn								// store rm pix counter

	rts											// done

////
// Clear pixels
clearpixels:
	ldx #00									
	
	cpx pixcn								// Ignore first run
	bne !+
	rts
!:
	lda pixrm, x						// Retrieve low byte
	sta clearaddr1
	inx
	lda pixrm, x
	sta clearaddr1+1				// retrieve high byte
	inx

	lda #0
	sta clearaddr1:$FFFF		// Clear display byte
	cpx pixcn
	bne !-									

	lda #$00
	sta pixcn								// Reset the pixelcounter

rts
	
	

////
// Clear the display memory
clearbitmap:
  ldx #$00
	txa
!:
  sta clraddr:$2000, x  // write 0 to display memory
  inx
  bne !-                  

  inc clraddr+1         // Next segment
  lda #$40
  cmp clraddr+1         // We want to count until $3FFF, so $4000 is exit
  bne clearbitmap

rts

BasicUpstart2(begin)      // <- This creates a basic sys line that can start your program

//*************************************************
//* Sinus animation in Bitplain                   *
//*************************************************

// Vars
xpix: .word $0000   // X position to draw the pixel to
ypix: .byte $00     // Y position to draw the pixel to

// Zero page

// C64 memory map
.const SCRCONTREG  = $D011 // Screen control register
.const MEMSETREG   = $D018 // VIC II memory map control
.const INTCONTREG1 = $DC0D // CIA 1 Interrupt control
.const INTCONTREG2 = $DD0D // CIA 2 Interrupt control

.pc = $9000 "Data"
.align $40

// Sinus lookup table
.var i=0
.var len=320
sinus:
.while (i++<len) {
  .var x = round(200-(50*sin((i*2*PI)/(len))))
  .print x
  .byte x 
}

// 8 value mask table
bytemask:
.for(var count=0; count<8; count++){
  .byte (1<<count)
  .print (1<<count)
}

// Screen memory Y axis lookup table
.pc = $9200 "Yoffset table"
yoffset:
.var countloop=0
.for(var base=$2000; base<$3FFF; base=base+$140) {
  .for(var offset=0; offset<8; offset++) {
    .word (base+offset)
    .print "" + (countloop) + ":"  + (base+offset-8192) + " : " + (base+offset)
    .eval countloop = countloop+2
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

  // 
  // Clear the display memory
!begin:
  ldx #$00
  lda #$00
!loop:
  sta clraddr:$2000, x  // write 0 to display memory
  inx
  bne !loop-                  

  inc clraddr+1         // Next segment
  lda #$40
  cmp clraddr+1         // We want to count until $3FFF, so $4000 is exit
  bne !begin- 




//  // 
//  // Bar on the right of the screen
//  ldy #$00
//  ldx #0
//!loop:
//  ldy #$FF
//  sty dispaddr:$2000
//  lda yoffset, x
//  sta dispaddr
//  inx
//  lda yoffset, x
//  sta dispaddr+1
//  inx
//  txa
//  cmp #$80
//  bne !loop-


  ldx #0
!loop:
  lda copy1:$9200, x   // load the lower byte into A
  sta dispaddr1    // store it in the display address

  lda copy2:$9200+1, x   // load the upper byte into A
  sta dispaddr1+1  // store it in the display address
  inx              // to next word
  inx              // to next byte

  bne !+           // Trigger on 255 -> 0 (256)
  inc copy1+1    // DEBUG destructive, but good enough for now  
  inc copy2+1    // DEBUG destructive, but good enough for now  

  lda #$3          // debug
  sta $D020
!:

  lda #$55         // All bytes to one to display
  sta dispaddr1:$FFFF   // set the bytes
  lda dispaddr1+1  // Did we reach $3fff yet?
  cmp $3F
  bne !loop-

  // debug
  lda #$1
  sta $D020

  // Ad infinum
  jmp *

  rts 
  

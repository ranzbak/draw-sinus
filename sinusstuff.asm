BasicUpstart2(begin)      // <- This creates a basic sys line that can start your program

//*************************************************
//* Sinus animation in Bitplain                   *
//*************************************************

// Raster debug ?
.const DEBUG = 0

// Vars
xpix:    .word $0000   // X position to draw the pixel to
ypix:    .byte $00     // Y position to draw the pixel to
anoff:   .byte $00     // Animation offset
piroffx:  .byte $00    // Period offset
piroffy:  .byte $21    // Period offset
pixrm:   .fill 100, 0  // List of bytes to remove
pixcn:   .byte 0       // Array counter

// Zero page helper address ??
.const ZP_HELPADR      = $FB

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

.pc = $2000 "Sprites"

//*** Zero the 8 sprites
.pc = $2000 "Data"
.align $400
sprite0: .fill 64, 0
sprite1: .fill 64, 0
sprite2: .fill 64, 0
sprite3: .fill 64, 0
sprite4: .fill 64, 0
sprite5: .fill 64, 0
sprite6: .fill 64, 0
sprite7: .fill 64, 0

.pc = $9000 "Data"
.align $40

// Sinus lookup table
.var i=0
.var len=256
sintab:
.while (i++<len) {
  .var x = round(100-(50*sin((i*2*PI)/(len))))
  //.print "" + i + " value: " + x
  .byte x
}

// 8 value mask table
bitmask:
.for(var count=0; count<8; count++){
  .byte (128>>count)
  //.print (128>>count)
}

// Screen memory Y axis lookup table
.pc = $9200 "Yoffset table"
.align $100
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
  lda #$00     // First fow rows all black to hide sprite memory
!clear:
  sta $0400,x  // fill four areas with 256 spacebar characters
  inx           // increment X
  bne !clear-   // did X turn to zero yet?
  lda #$10      // After that white for effect
!clear:
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

	// Setup the sprites in the scroller
	jsr setup_sprites

  // Setup the raster interrupt
  jsr raster_init

  // Start teh main routine
  asl INTSTATREG        // Ack any previous raster interrupt
  bit $dc0d             // reading the interrupt control registers
  bit $dd0d             // clears them
  cli                   // Enable interrupts again

////
// Ad infinum
  jmp *

  rts

////
// Raster interrupt routine
effect_irq:
// save registers
  pha
  txa
  pha
  tya
  pha

// Debug
.if (DEBUG==1) {
  lda #1                // To White
  sta $d020
}

  lda #$ff              // Acknowledge interrupt
  sta $d019

// Clear the last run
  jsr clearpixels

// Move sprites to the top
	jsr sprite_top

// Debug
.if (DEBUG==1) {
  lda #2                // To brown
  sta $d020
}

// Draw some pixels
  lda #$00
  sta xpix + 1


  lda #$07            // Mask lower 3 bits, to animate 0-7
  and anoff           // Pixel offset
  inc anoff
  ldx #$00
  inc piroffx         // change period
!:
  pha
	asl									// 2 times xphase compared ot y phase
	asl									// 2 times xphase compared ot y phase
  adc piroffy         // Y progression
  tay
  lda sintab,y        // Sinus X lookup

  clc
  ldy #$00            // Y = 0
  adc #$32            // move cicle

  sta xpix            // Set X draw coordinate

  pla
  pha                 // Store the counter

  adc piroffx         // period offset sinus wave X
  tay                 // Lookup Y from sinus table
  lda sintab, y
  sta ypix

  txa                 // Store the X register
  pha

  jsr drawpixel       // Draw the pixel that

  pla                 // Restore the X
  tax
  pla                 // Restore A

  clc
  adc #$08
  inx
  cpx #$20
  bne !-

	// Back to the effect IRQ
  lda #<scroller_irq
  sta INTVEC
  lda #>scroller_irq
  sta INTVEC+1

  // Trigger at raster line 200
  ldy #90
  sty $d012

  // Debug
.if (DEBUG==1) {
  lda #0
  sta $d020
}

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

  lda #<effect_irq
  sta INTVEC
  lda #>effect_irq
  sta INTVEC+1
  lda #%00000001
  sta INTSTATREG
  sta INTVICCONTREG
  rts

////
// Setup the sprites
setup_sprites:
  ldx #sprite0/64               // Calculate sprite start address
  stx $07F8
  inx
  stx $07F9
  inx
  stx $07FA
  inx
  stx $07FB
  inx
  stx $07FC
  inx
  stx $07FD
  inx
  stx $07FE


  lda #$32                      //Y-Position for all sprites
  sta $D001
  sta $D003
  sta $D005
  sta $D007
  sta $D009
  sta $D00B
  sta $D00D

  lda #$18                      //X-Position for all sprites
  sta $D000
  lda #$48
  sta $D002
  lda #$78
  sta $D004
  lda #$A8
  sta $D006
  lda #$D8
  sta $D008
  lda #$08
  sta $D00A
  lda #$38
  sta $D00C

  lda #%01100000                //X-Pos for Sprite 5 & 6 > 255
  sta $D010

  lda #$03                      // Color yellow for all sprites
  sta $D027
  sta $D028
  sta $D029
  sta $D02A
  sta $D02B
  sta $D02C
  sta $D02D

  lda #%01111111                // Dubble the first 7 sprites in heigt and depth
  sta $D01D                     
  sta $D017                     
  sta $D015                     
	rts

sprite_top:
.if (DEBUG==1) {
	lda #$03
	sta $D020
}
  lda #$32                      //Y-Position for all sprites
  sta $D001
  sta $D003
  sta $D005
  sta $D007
  sta $D009
  sta $D00B
  sta $D00D
	rts

sprite_bottom:
  lda #$E5                      //Y-Position for all sprites
  sta $D001
  sta $D003
  sta $D005
  sta $D007
  sta $D009
  sta $D00B
  sta $D00D
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
  lda ypix              // ypix offset times 2
  rol
  sta drawyofflo
  sta drawyoffhi

  bcc !+                // If an overflow occurs, add one to the msb
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
  lda #%11111000          // calculate the lsb offset
  and xpix

  clc                     // Store in the drawaddr lsb
  adc drawaddr
  sta drawaddr

  lda xpix+1              // Get the X msb, add it to the drawaddr msb + carry
  adc drawaddr+1
  sta drawaddr+1

  // Or mask byte
  lda #%00000111
  and xpix
  tax
  lda bitmask, x          // get the correct bitmask

  sta drawaddr:$FFFF      // Just put the pixel clearing the other 7 pixels *LAZY*

  // store the location in the erase arrey
  ldx pixcn               // Get the pixel counter
  lda drawaddr            // Get the draw addr low byte
  sta pixrm, x            // Store low byte
  inx
  lda drawaddr+1          // High byte
  sta pixrm, x
  inx
  stx pixcn               // store rm pix counter

  rts                     // done

////
// Clear pixels
clearpixels:
  ldx #00

  cpx pixcn               // Ignore first run
  bne !+
  rts
!:
  lda pixrm, x            // Retrieve low byte
  sta clearaddr1
  inx
  lda pixrm, x
  sta clearaddr1+1        // retrieve high byte
  inx

  lda #0
  sta clearaddr1:$FFFF    // Clear display byte
  cpx pixcn
  bne !-

  lda #$00
  sta pixcn               // Reset the pixelcounter

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

  //*** Raster-IRQ
scroller_irq:
  // save registers
  pha
  txa
  pha
  tya
  pha

  // Border to yellow
.if (DEBUG==1) {
  lda #07
  sta $D020
}

  // Ack interrupt
  lda #$ff                       // Acknowledge interrupt
  sta $d019

  dec infotextbitpos            //wurden bereits 8-Bits 'verschoben'
  bpl shiftall                  //falls nein, alle Spritedaten 'shiften'
  lda #$07                      //sonst Zähler zurücksetzen
  sta infotextbitpos            //und dann nächstes Zeichen holen
  inc infotextpos               //Zeiger aufs nächste Zeichen erhöhen
  ldx infotextpos               //und ins X-Register holen
  lda infotext,X                //Zeichen in den Akku
  bne getChar                   //falls kein Textende ($00) weiter bei getChar
  ldx #$00                      //sonst Zeiger aufs erste Zeichen
  stx infotextpos               //zurückstellen
  lda infotext                  //und das Zeichen in den Akku holen

  getChar:                        //ein Zeichen aus dem Char-ROM holen

  tax                           //Zeichen ins X-Register

  sei                          // Disable interrupts
  lda #$31                       // Character rom visible 
  sta $01                      // Set memory bank register

  lda #$00                      //Startadresse des Char-ROMs auf die Zero-Page
  sta ZP_HELPADR
  lda #$D0
  sta ZP_HELPADR+1
!:                             //Jetzt für jedes Zeichen, bis zum gesuchten,
  clc                           //8-BYTEs auf die Char-ROM-Adresse in der
  lda #$08                      //Zero-Page addieren
  adc ZP_HELPADR
  sta ZP_HELPADR
  lda #$00
  adc ZP_HELPADR+1
  sta ZP_HELPADR+1
  dex
  bne !-

  lda #%11111011                //E/A-Bereich abschalten, um aufs Char-ROM
  and $01                       //zugreifen zu können
  sta $01

  ldy #$00                      //Y-Reg. für die Y-nach-indizierte-Adressierung
  lda (ZP_HELPADR),Y            //jeweils ein BYTE aus dem Char-ROM
  sta sprite7+2                 //ganz nach rechts in Sprite-7 kopieren
  iny                           //Y fürs nächste BYTE erhöhen
  lda (ZP_HELPADR),Y
  sta sprite7+5
  iny
  lda (ZP_HELPADR),Y
  sta sprite7+8
  iny
  lda (ZP_HELPADR),Y
  sta sprite7+11
  iny
  lda (ZP_HELPADR),Y
  sta sprite7+14
  iny
  lda (ZP_HELPADR),Y
  sta sprite7+17
  iny
  lda (ZP_HELPADR),Y
  sta sprite7+20
  iny
  lda (ZP_HELPADR),Y
  sta sprite7+23

  lda #%00000100                //E/A-Bereich wieder aktivieren
  ora $01
  sta $01


  //!zone shiftall
shiftall:
  ldx #3*7                      // 3 bytes horizontally, 8 vertically
!:
  clc                           // Clear carry
  rol sprite7+2,X               // Roll all bytes one to teh left
  rol sprite7+1,X               
  rol sprite7,X                 
  rol sprite6+2,X
  rol sprite6+1,X
  rol sprite6,X
  rol sprite5+2,X
  rol sprite5+1,X
  rol sprite5,X
  rol sprite4+2,X
  rol sprite4+1,X
  rol sprite4,X
  rol sprite3+2,X
  rol sprite3+1,X
  rol sprite3,X
  rol sprite2+2,X
  rol sprite2+1,X
  rol sprite2,X
  rol sprite1+2,X
  rol sprite1+1,X
  rol sprite1,X
  rol sprite0+2,X
  rol sprite0+1,X
  rol sprite0,X
  dex                           //das X-Register dreimal verringer
  dex                           //da wir oben immer drei BYTEs auf einmal
  dex                           //'shiften'
  bpl !-                     //solange positiv -> wiederholen

  lda $D019                     //IRQ bestätigen
  sta $D019

.if (DEBUG==1) {
  lda #00
  sta $D020
}

  // Trigger at raster line 200
  ldy #100
  sty $d012

  // Bank memory back out
  lda #$35
  sta $01

	// Sprites to the bottom of the screen
	jsr sprite_bottom

	// Back to the effect IRQ
  lda #<effect_irq
  sta INTVEC
  lda #>effect_irq
  sta INTVEC+1

  // Trigger at raster line 200
  ldy #210
  sty $d012

  cli                          // Enable interupts again

  // Restore registers
  pla
  tay
  pla
  tax
  pla

  rti                           // Return from Interrupt

infotext:                       // Scroller text
  // !convtab scr
  .text "this sprite scroller will be a pain to combine with the pixel effect below, where do we get the raster time?? i don't know but we'll see i guess...... "
  .byte $00                      // Terminator

infotextpos:                    // Text pointer
  .byte $FF

infotextbitpos:
  .byte $00

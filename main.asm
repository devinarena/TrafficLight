;
; TrafficLight.asm
;
; Created: 12/8/2020 3:02:02 PM
; Author : Devin Arena
; Purpose: Simulate a traffic signal cycle using timers. Use a push button with interrupts to simulate pressing
;          a crosswalk button. Makes use of 4 LEDs, a push button, 4 330ohm resistors, 1 10kohm resistor and 7 wires.

.DEF TEMP = R16 ; TEMP register to store data temporarily
.DEF LEDI = R17 ; LEDI contains the index of the LED to light
.DEF TINC = R18 ; TINC stores the number of iterations of Timer1
.DEF INIT = R24 ; Tracks if main has run to init already

.EQU TIMVAL = 0xC2F7 ; value to store in the timer
.EQU TIMITR = 8      ; how many times to iterare for the timer, timer runs for 1,000,000us (1 second)
                     ; this is just how many seconds each light is active for
.EQU RED    = 3      ; red is the first light in the cycle and is on PORTC3
.EQU GREEN  = 4      ; green is the second light in the cycle and is on PORTC4
.EQU YELLOW = 5      ; yello is the last light in the cycle and is on PORTC5

.ORG 0x0000                   ; reset interrupt address and start of the program
          RJMP      main      ; jump back to main
.ORG INT0addr                 ; external interrupt address for the button, triggers when button is pressed
          RJMP      btn_press ; jump to button press method
.ORG OVF1addr                 ; timer overflow interrupt address, triggers when the timer overflows
          RJMP      led_cycle ; jump to the LED cycle method

.ORG INT_VECTORS_SIZE         ; start main program AFTER interrupt vectors
main:
          CPI       INIT,0    ; check if stack pointer, io and interrupts have been setup already
          BRNE      lights    ; if so just return to endless loop
          ; initialize stack pointer
          LDI       TEMP,HIGH(RAMEND)   ; load high byte of ramend
          OUT       SPH,TEMP            ; store in stack pointer high
          LDI       TEMP,LOW(RAMEND)    ; load low byte of ramend
          OUT       SPL,TEMP            ; store in stack pointer low

          ; setup IO ports
          SBI       DDRC,DDC3           ; PORTC3 is used for output
          SBI       DDRC,DDC4           ; PORTC4 is used for output
          SBI       DDRC,DDC5           ; PORTC5 is used for output
          SBI       DDRC,DDB0           ; PORTD1 is used for output
          SBI       PORTC,PORTC3        ; PORTC5 should be on initially (green light)
          CBI       DDRD,DDD2           ; PORTD2 is used for input (INT0)
          SBI       PORTD,PORTD2        ; PORTD2 is pull-up for interrupt

          ; setup external interrupt
          LDI       TEMP,(1<<INT0)      ; enable INT0
          OUT       EIMSK,TEMP          ; store in EIMSK register

          LDI       TEMP,(1<<ISC01)     ; set INT0 to be falling edge triggered (button pushed down)
          STS       EICRA,TEMP          ; store in EICRA register

          ; setup timer and timer interrupt
          LDI       TEMP,(1<<TOIE1)     ; enable timer overflow interrupt for timer1
          STS       TIMSK1,TEMP         ; store in TIMSK1 register

          LDI       TEMP,HIGH(TIMVAL)   ; load high byte of timer value (value makes timer run for 1 second)
          STS       TCNT1H,TEMP         ; place into timer 1 counter high register
          LDI       TEMP,LOW(TIMVAL)    ; load low byte of timer value (value makes timer run for 1 second)
          STS       TCNT1L,TEMP         ; place into timer 1 counter low register
          CLR       TEMP                ; use normal mode for timer1
          STS       TCCR1A,TEMP         ; store to TCCR1A register
          LDI       TEMP,(1<<CS12|1<<CS10)        ; use clk/1024 as prescaler
          STS       TCCR1B,TEMP         ; store to TCCR1B register

          LDI       TINC,TIMITR         ; load timer increment register with timer iterations variable
          LDI       LEDI,(1<<RED)       ; load LED index register with value of red LED

          SEI                           ; enable global interrupts

          INC       INIT                ; don't init more than once

lights:   RJMP      lights              ; endless loop, waiting for interrupts
          
; Called when the button is pressed, checks if it has been pressed already and if the light is red
; before turning setting PORTB0 to turn the LED on (and store whether the button has been pressed)
; and changing the clock prescaler to 256 to increase the timer speed until the light is red again.
btn_press:
          SBIC      PINB,PINB0          ; if PINB0 is set, the button has been pressed this cycle
          RJMP      pressed             ; do nothing if the button as pressed
          SBIC      PORTC,RED           ; if the light is red, do nothing, they can already walk accross
          RJMP      pressed             ; no need to speed up the light if its already red
          LDI       TEMP,0b00000000|(1<<CS12)     ; set the clock prescaler to clk/256
          STS       TCCR1B,TEMP         ; this will increase the speed of the green and yellow cycles
          SBI       PORTB,PORTB0        ; turn the LED on, functions as the indicator that the button has been pressed
pressed:
          RETI                          ; return from interrupt
 
; Called when the timer overflow interrupt occurrs (once a second), after the number of increments from TIMITR
; occurr, the light cycles, the increment is reset and if the light turns red again, the clock prescaler is reset
; to make sure people have time to walk. 
led_cycle:
loop:
          LDI       TEMP,HIGH(TIMVAL)   ; reset the high value of the timer counter
          STS       TCNT1H,TEMP         ; reset the high value of the timer counter
          LDI       TEMP,LOW(TIMVAL)    ; reset the low value of the timer counter
          STS       TCNT1L,TEMP         ; reset the low value of the timer counter
          DEC       TINC                ; decrement the timer incremental counter
          BRNE      no_change           ; if the specified number of cycles have not passed, don't change the light

          ; reset 
          LDI       TINC,TIMITR         ; reset the increment timer 

          LSL       LEDI                ; shift LED index left, moves from PORTC3(RED)->PORTC4(GREEN)-PORTC5(YELLOW) 
          CPI       LEDI,0b01000000     ; PORTC6 is out of bounds of the LEDs, so now we need to reset to red light
          BRNE      no_change           ; if not out of bounds, don't continue to reset
          LDI       LEDI,(0b00000000|1<<RED)      ; reset LED index to red
          
          SBIS      PINB,PINB0          ; PINB0 is cleared, theres no need to reset the clock prescaler
          RJMP      no_change           ; otherwise reset the clock pointer
          LDI       TEMP,0b00000000|(1<<CS12|1<<CS10)       ; sets clock pointer to clk/1024, our original value
          STS       TCCR1B,TEMP         ; the cycle will now take 8 seconds again
          CBI       PORTB,PORTB0        ; turn the LED off so the button can be pressed once more
no_change:
          OUT       PORTC,LEDI          ; turn on the proper LED and turn the others off
          RETI                          ; return from interrupt
#!/usr/bin/env python

import RP64.GPIO as GPIO
import time
from subprocess import call
var_gpio_out = 15

GPIO.setwarnings(False)
GPIO.setmode(GPIO.BOARD)
GPIO.setup(var_gpio_out, GPIO.OUT, initial=GPIO.HIGH)

print ('LED check')
#time.sleep(3)
GPIO.output(var_gpio_out, GPIO.LOW)

for i in range(0,10):
        GPIO.output(var_gpio_out, GPIO.HIGH)
        time.sleep(0.5)
        GPIO.output(var_gpio_out, GPIO.LOW)
        time.sleep(0.5)

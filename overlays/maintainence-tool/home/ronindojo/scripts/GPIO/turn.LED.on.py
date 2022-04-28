#!/usr/bin/env python

import RP64.GPIO as GPIO

var_gpio_out = 15

GPIO.setwarnings(False)
GPIO.setmode(GPIO.BOARD)
GPIO.setup(var_gpio_out, GPIO.OUT, initial=GPIO.HIGH)
GPIO.cleanup([var_gpio_out])

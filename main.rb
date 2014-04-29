#!/usr/bin/env ruby

require 'travis'
require 'tinkerforge/ip_connection'
require 'tinkerforge/bricklet_lcd_20x4'
require 'tinkerforge/bricklet_dual_relay'
require 'dotenv'
require 'colorize'

Dotenv.load

include Tinkerforge
tfConnection = Tinkerforge::IPConnection.new
tfConnection.connect ENV["TINKERFORGE_HOST"], ENV["TINKERFORGE_PORT"]

class BuildStatusInformation

  def initialize(build)
    @width = 20
    self.lines = []
    self.lines << center("#{build.commit.author_name}")
  end

  private 
    def alignLeft(str)

    end

    def center(str, padding=" ")
      return str.center(@width, padding)
    end
end

class Lamp
  attr_accessor :relay
  def initialize(uid, tfConnection) 
    self.relay = Tinkerforge::BrickletDualRelay.new uid, tfConnection
  end

  def green!
    self.relay.set_state false, true
  end

  def blink_once_green!
    self.relay.set_monoflop(2, true, 1000)
  end

  def red!
    self.relay.set_state true, false
  end

  def blink_once_red!
    self.relay.set_monoflop(1, true, 1000)
  end

  def yellow!
    self.relay.set_state false, false
  end

  def off!
    self.relay.set_state true, true
  end

  def color(newColor)
    case newColor
      when "red" then self.red!
      when "green" then self.green!
      when "yellow" then self.yellow!
      else lamp.off!
    end
  end
end

class Display
  attr_accessor :display
  def initialize(uid, tfConnection)
    self.display = Tinkerforge::BrickletLCD20x4.new uid, tfConnection
    self.display.backlight_on
  end

  def print_build_info(build)
    self.display.clear_display
    self.display.write_line(0,0,"#{build.commit.author_name}".center(20, " "))
    self.display.write_line(1,0,"\##{build.commit.short_sha} (#{build.branch_info})")
    if build.finished?
      self.display.write_line(2,0,"Build \##{build.number} at #{build.finished_at.getlocal.strftime("%k:%M")}")
      self.display.write_line(3,0," #{build.state.upcase} ".center(20,"="))
    else
      self.display.write_line(2,0,"Build \##{build.number} at #{build.started_at.getlocal.strftime("%k:%M")}")
      self.display.write_line(3,0," IN PROGRESS ".center(20, "*"))
    end
    self.display.backlight_on
  end 

  def print_disconnected
    self.display.clear_display
    self.display.write_line(0, 0, "Client not running".center(20, " "))
  end
end

lamp = Lamp.new ENV["TINKERFORGE_RELAY_UID"], tfConnection
display = Display.new ENV["TINKERFORGE_LCD_UID"], tfConnection

Travis::Pro.access_token=ENV["TRAVIS_PRO_ACCESS_TOKEN"]

begin
  repo = Travis::Pro::Repository.find(ENV["REPOSITORY"])
  last_build = repo.builds({branch: "master"}).detect{ |b| b.finished? or b.started? }
  
  display.print_build_info(last_build)
  last_finished_build = repo.builds(branch: "master").detect { |b| b.finished? }
  puts "Build tracker running".green
  if (last_finished_build.red?)
    lamp.color last_build.color
    puts "The last build failed".red
  else
    lamp.color last_finished_build.color
    puts "All good".green
  end

  Travis::Pro.listen(repo) do |stream|
    stream.on('build:finished', 'build:started') do |event|
      puts "Event: #{event}"
      puts "Build: #{event.repository.slug} just #{event.build.state} (build number #{event.build.number})"
      repo.reload
      build = repo.build(event.build.number)
      puts build.branch_info
      if build.branch_info == "master"
        last_finished_build = repo.builds(branch: "master").detect { |b| b.finished? }
        display.print_build_info(build)
        puts "Current build(#{build.number}) -> #{build.color}"
        puts "Last finished build(#{last_finished_build.number}) -> #{last_finished_build.color}"
      if (event.type == "build:finished" or last_finished_build.red?)
        lamp.color build.color
      else 
        lamp.color last_finished_build.color
      end
    end
    end
  end
rescue StandardError, Interrupt
  display.print_disconnected
  lamp.off!
  tfConnection.disconnect
  raise
end


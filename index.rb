# frozen_string_literal: true

require 'blizzard_api'
require 'sinatra'
require 'mini_magick'

set :bind, '0.0.0.0'
use Rack::Deflater

BlizzardApi.configure do |config|
  config.region = ENV.fetch 'REGION', 'us'
  config.app_id = ENV['BNET_APPLICATION_ID']
  config.app_secret = ENV['BNET_APPLICATION_SECRET']

  if ENV.fetch('USE_CACHE', 'false') == 'true'
    config.use_cache = true
    config.redis_host = ENV['REDIS_HOST']
    config.redis_port = ENV['REDIS_PORT']
  end
end

def get_character(realm, name)
  profile_api = BlizzardApi::Wow.character_profile
  summary = profile_api.get realm, name
  media = profile_api.media realm, name

  guild_name = summary.dig(:guild, :name)
  guild_name = "<#{guild_name}>" if guild_name

  summary.slice(:name, :level, :average_item_level, :equipped_item_level, :achievement_points)
    &.merge({
              class_name: summary.dig(:character_class, :name, :en_US),
              guild_name: guild_name,
              realm_name: summary.dig(:realm, :name, :en_US),
              faction: summary.dig(:faction, :type),
              media: media[:assets].find { |asset| asset[:key].eql? 'inset' }
            })
end

def get_image(character_data)
  avatar = MiniMagick::Image.open(character_data[:media][:value])
  bg = MiniMagick::Image.open("./images/background-#{character_data[:faction]}.png")
  empty = MiniMagick::Image.open('./empty.png')

  sig = empty.composite(avatar) do |c|
    c.geometry('+2+2')
  end.composite(bg)

  sig.combine_options do |i|
    i.font('./fonts/merriweather/Merriweather-Bold.ttf')
    i.pointsize(30)
    i.fill('#deaa00')
    i.draw("text 220,40 '#{character_data[:name]}'")
    i.font('./fonts/merriweather/Merriweather-Regular.ttf')
    i.pointsize(12)
    i.fill('#888888')
    i.draw("text 220,65 'Level #{character_data[:level]} #{character_data[:class_name]} #{character_data[:guild_name]} on #{character_data[:realm]}'")
    i.draw("text 220,85  'Item Level: #{character_data[:average_item_level]} (#{character_data[:equipped_item_level]}))'")
    i.draw("text 220,105 'Achievement Points: #{character_data[:achievement_points]}'")
  end.to_blob
end

def get_signature(realm, name)
  character_data = get_character(realm, name)
  get_image(character_data)
end

get '/' do
  'Use the following path to test: /signature/:realm/:name'
end

get '/signature/:realm/:name' do |realm, name|
  content_type 'image/png'
  get_signature(realm, name)
end

error BlizzardApi::ApiException do
  'Failed to fetch data from the API, check the realm and character names or your credentials.'
end

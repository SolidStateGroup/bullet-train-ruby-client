# frozen_string_literal: true

require 'faraday'
require 'faraday_middleware'

# Ruby client for flagsmith.com
class Flagsmith
  attr_reader :flagsmith_api

  def initialize(opts = {})
    @opts = determine_opts(opts)

    @flagsmith_api = Faraday.new(url: @opts[:url]) do |faraday|
      faraday.headers['Accept'] = 'application/json'
      faraday.headers['Content-Type'] = 'application/json'
      faraday.headers['x-environment-key'] = @opts[:api_key]
      faraday.response :json
      # TODO: add timeout adjustment here
      faraday.adapter Faraday.default_adapter
    end
  end

  def get_flags(user_id = nil)
    if user_id.nil?
      res = @flagsmith_api.get('flags/')
      flags = transform_flags(res.body).select { |flag| flag[:segment].nil? }
      flags_to_hash(flags)
    else
      res = @flagsmith_api.get("identities/?identifier=#{user_id}")
      flags_to_hash(transform_flags(res.body['flags']))
    end
  end

  def feature_enabled?(feature, user_id = nil, default = false)
    flag = get_flags(user_id)[normalize_key(feature)]
    return default if flag.nil?

    flag[:enabled]
  end

  def get_value(key, user_id = nil, default = nil)
    flag = get_flags(user_id)[normalize_key(key)]
    return default if flag.nil?

    flag[:value]
  end

  def set_trait(user_id, trait, value)
    raise StandardError, 'user_id cannot be nil' if user_id.nil?

    trait = {
         identity:    { identifier: user_id },
        trait_key:    normalize_key(trait),
      trait_value:    value
    }
    res = @flagsmith_api.post('traits/', trait.to_json)
    res.body
  end

  def get_traits(user_id)
    return {} if user_id.nil?

    res = @flagsmith_api.get("identities/?identifier=#{user_id}")
    traits_to_hash(res.body)
  end

  # def remove_trait(user_id, trait_id)
  #   # Request URL: https://api.flagsmith.com/api/v1/environments/API_KEY/identities/12345/traits/54321/
  #   # Request Method: DELETE
  # end

  def transform_flags(flags)
    flags.map do |flag|
      {
           name:    flag['feature']['name'],
        enabled:    flag['enabled'],
          value:    flag['feature_state_value'],
        segment:    flag['feature_segment']
      }
    end
  end

  def flags_to_hash(flags)
    result = {}
    flags.each do |flag|
      key = normalize_key(flag.delete(:name))
      result[key] = flag
    end
    result
  end

  def traits_to_hash(user_flags)
    result = {}
    user_flags['traits']&.each do |t|
      key = normalize_key(t['trait_key'])
      result[key] = t['trait_value']
    end
    result
  end

  def normalize_key(key)
    key.to_s.downcase
  end

  def determine_opts(opts)
    opts = { api_key: opts } if opts.is_a? String

    {
      api_key: opts[:api_key] || self.class.api_key,
          url: opts[:url] || self.class.api_url
    }
  end

  def self.api_key
    ENV['FLAGSMITH_API_KEY']
  end

  def self.api_url
    ENV.fetch('FLAGSMITH_URL', 'https://api.flagsmith.com/api/v1/')
  end
end

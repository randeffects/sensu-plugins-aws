#! /usr/bin/env ruby
#
# check-s3-bucket-visibility
#
# DESCRIPTION:
#   This plugin checks a bucket for website configuration and bucket policy.
#   It alerts if the bucket has a website configuration, or a policy that has
#   Get or List actions.
#
# OUTPUT:
#   plain-text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: aws-sdk
#   gem: sensu-plugin
#
# USAGE:
#   ./check-s3-bucket-visibility.rb --bucket-name mybucket --aws-region eu-west-1
#
# NOTES:
#
# LICENSE:
#   Copyright (c) 2015, Olivier Bazoud and Ricky Hussmann,
#     olivier.bazoud@gmail.com, ricky.hussmann@gmail.com
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'aws-sdk'
require 'sensu-plugin/check/cli'
require 'sensu-plugins-aws'

class CheckS3Bucket < Sensu::Plugin::Check::CLI
  include Common
  option :aws_region,
         short: '-r AWS_REGION',
         long: '--aws-region REGION',
         description: 'AWS Region (defaults to us-east-1).',
         default: 'us-east-1'

  option :bucket_names,
         short: '-b BUCKET_NAMES',
         long: '--bucket-names',
         description: 'A comma seperated list of S3 buckets to check'

  option :critical_on_missing,
         short: '-m ',
         long: '--critical-on-missing',
         description: 'The check will fail with CRITICAL rather than WARN when a bucket is not found',
         default: 'false'

  def true?(obj)
    !obj.nil? && obj.to_s.casecmp('true') != -1
  end

  def s3_client
    @s3_client ||= Aws::S3::Client.new
  end

  def website_configuration?(bucket_name)
    s3_client.get_bucket_website(bucket: bucket_name)
    true
  rescue Aws::S3::Errors::NoSuchWebsiteConfiguration
    false
  end

  def get_bucket_policy(bucket_name)
    JSON.parse(s3_client.get_bucket_policy(bucket: bucket_name).policy.string)
  rescue Aws::S3::Errors::NoSuchBucketPolicy
    { 'Statement' => [] }
  end

  def policy_too_permissive?(policy)
    policy['Statement'].any? { |s| statement_too_permissive? s }
  end

  def statement_too_permissive?(s)
    actions_contain_get_or_list? Array(s['Action'])
  end

  def actions_contain_get_or_list?(actions)
    actions.any? { |a| !Array(a).grep(/^s3:Get|s3:List|s3:\*/).empty? }
  end

  def run
    errors = []
    warnings = []
    buckets = config[:bucket_names].split ','

    buckets.each do |bucket_name|
      begin
        if website_configuration?(bucket_name)
          errors.push "#{bucket_name}: website configuration found"
        end
        if policy_too_permissive?(get_bucket_policy(bucket_name))
          errors.push "#{bucket_name}: bucket policy too permissive"
        end
      rescue Aws::S3::Errors::NoSuchBucket => _
        mesg = "Bucket #{bucket_name} not found"
        true?(config[:critical_on_missing]) ? errors.push(mesg) : warnings.push(mesg)
      end
    end

    if !errors.empty?
      critical errors.join '; '
    elsif !warnings.empty?
      warning warnings.join '; '
    else
      ok "#{buckets.join ','} not exposed via website or bucket policy"
    end
  end
end

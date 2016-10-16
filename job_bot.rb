#!/usr/bin/env ruby
require "selenium-webdriver"
require "byebug"
require 'yaml'
require 'ruby-progressbar'

class JobBot
		CONFIG = YAML.load_file('config.yaml')

		EMAIL = CONFIG['linked_in']['email']
		PASSWORD = CONFIG['linked_in']['password']
		PHONE_NUM = CONFIG['linked_in']['phone_num']
		PATH_TO_RESUME = CONFIG['linked_in']['resume_path']
		FOLLOW_COMPANIES = CONFIG['linked_in']['follow_companies']


		FILTERS = CONFIG['settings']['filters'].map(&:downcase)
		TESTING = CONFIG['settings']['testing']
		LOAD_TIME = CONFIG['settings']['load_time']
		JOB_BATCH_NUM = 2
		BATCH_NUM = CONFIG['zip_recruiter']['batch_num']

		APPLY_ID = "apply-job-button"
		JOBS_PAGE = "https://www.linkedin.com/jobs/?trk=nav_responsive_sub_nav_jobs"
		HOME = "https://www.linkedin.com/uas/login?trk=guest_jobs_homepage"

	def initialize

		if ARGV[0] && ARGV[0].include?('help')
			puts "-l or linked for LinkedIn-Bot"
			puts "-z or zip for ZipRecruiter-Bot"
			puts "errors may be due to an incomplete config.yaml file"
			return
		end

		unless ARGV[0] && (ARGV[0].include?('linked') || ARGV[0].include?('-l') || ARGV[0].include?('zip') || ARGV[0].include?('-z'))
			puts "Invalid usage. Must add job application type: e.g. `ruby job_bot.rb linked`\n --help for more usage tips"
			return
		end


		@driver = Selenium::WebDriver.for :chrome
		filename = "JobBot:".concat(Time.now.to_s[0..15].split(" ").join("&"))
		@file = File.open(filename, 'w') unless TESTING


		if ARGV[0].include?('linked') || ARGV[0].include?('-l')
			linkedin_bot
		elsif ARGV[0].include?('zip') || ARGV[0].include?('-z')
			zip_bot
		end
		@driver.quit
		@file.close unless TESTING


	end

	def get_applied_jobs

		puts "Retrieving all previously applied to jobs"
		applied_jobs = []
		@driver.navigate.to "https://www.ziprecruiter.com/candidate/my-jobs"
		sleep(LOAD_TIME)

		while true
			next_button = @driver.find_element(:id, 'pagination-button-next')

			jobs = @driver.find_elements(:class, 'panel-heading')

			jobs.each do |job|

					job_info = {}
					position = job.find_element(:css, '.clickable_target > h4').text
					comp_and_location = job.find_elements(:css, '.mb0 > span > span')
					company_name, location = comp_and_location[0].text, comp_and_location[1].text

					job_info[:company_name] = company_name
					job_info[:position] = position
					job_info[:location] = location
					applied_jobs << job_info

			end

			if next_button.attribute('class').include?('disabled')
				break
			else
				next_button.click
				sleep(LOAD_TIME)
			end

		end

		applied_jobs

	end

	def zip_bot
		@file.write("   ZIP RECRUITER\n")
		@file.write("-"*20)
		@file.write("\n")

		@driver.navigate.to "https://www.ziprecruiter.com/login?realm=candidates"
		username = @driver.find_element(:name, 'email')
		username.send_keys CONFIG['zip_recruiter']['email']
		password = @driver.find_element(:name, 'password')
		password.send_keys CONFIG['zip_recruiter']['password']

		submit_button = @driver.find_element(:name, 'submitted')
		submit_button.click

		@applied_jobs = get_applied_jobs

		@driver.navigate.to "https://www.ziprecruiter.com/candidate/suggested-jobs"

		puts 'Applying to jobs'

		BATCH_NUM.times do |idx|

			get_and_apply_zip
			@driver.navigate.refresh unless (BATCH_NUM - idx) == 1

		end
	end



	def get_and_apply_zip
		sleep(LOAD_TIME)
		all_jobs = @driver.find_elements(:class, 'job_content')
		jobs = []

		all_jobs.each do |job|
			apply_button = job.find_element(:css, '.apply_area > a')
			jobs << job if apply_button.text == "1-Click Apply"
		end


		jobs.each do |job|

			company_name = job.find_element(:class, 'hiring_company_name').text
			position = job.find_element(:class, 'panel_job_title').text
			location = job.find_element(:class, 'job_location').text


			if @applied_jobs.none?{|job| job[:company_name] == company_name && job[:position] == position}
				apply_button = job.find_element(:css, '.apply_area > a')
				job_str = "#{company_name}: #{position} - (#{location})\n"
				puts "Applying to #{job_str}"
				apply_button.click
				@file.write(job_str)
			end
		end

	end


	def linkedin_bot
		@file.write("   LinkedIn\n")
		@file.write("-"*20)
		@file.write("\n")

		login
		sleep(LOAD_TIME)
		@driver.navigate.to JOBS_PAGE
		JOB_BATCH_NUM.times {show_more_jobs}
		get_job_links
		iterate_jobs

	end


	def login
		@driver.navigate.to HOME
		element = @driver.find_element(:name, 'session_key')
		element.send_keys EMAIL
		element = @driver.find_element(:name, 'session_password')
		element.send_keys PASSWORD
		element.submit
	end

	def get_job_links
		sleep(LOAD_TIME)

		puts @driver.title

		links = @driver.find_elements(:css,".item	> a").map{|link| link.attribute(:href)}
		companies = @driver.find_elements(:css,".job-info-container .col-right h3").map(&:text)
		titles = @driver.find_elements(:css,".job-info-container .col-right h2").map(&:text)
		companies = companies.map.with_index {|name, idx| name.concat(": #{titles[idx]}")}


		@jobs = {}
		companies.each.with_index do |company, idx|
			@jobs[company] = links[idx]
		end
	end

	def go_to(link)
		@driver.navigate.to link
	end

	def job_apply(apply_button, company)
		apply_button.click
		sleep(LOAD_TIME)


		if !FOLLOW_COMPANIES && !company.include?('linkedin')
			follow_radio_button = @driver.find_element(:name, 'followCompany')
			follow_radio_button.click
		end

		phone_field = @driver.find_element(:name, 'phone')
		phone_field.clear
		phone_field.send_keys PHONE_NUM

		resume_submit_button = @driver.find_element(:id, 'file-browse-input')
		resume_submit_button.send_keys(PATH_TO_RESUME)
		sleep(LOAD_TIME)

		submit_app_button = @driver.find_element(:id, 'send-application-button')

		unless TESTING
			submit_app_button.click
			puts "Applied to #{company}"
			@file.write("#{company}\n")
		end

		sleep(LOAD_TIME)
	end

	def is_job_acceptable?(apply_button, company)
		apply_button.any? && FILTERS.none?{|filter| company.downcase.include?(filter)}
	end

	def show_more_jobs
		sleep(LOAD_TIME)
		expand_button = @driver.find_element(:class, 'expand-button')
		expand_button.click
		sleep(LOAD_TIME)
	end

	def iterate_jobs
		@jobs.each do |company, link|
			puts "going to #{company}"
			go_to(link)
			sleep(LOAD_TIME)
			apply_button = @driver.find_elements(:id, 'apply-job-button')
			job_apply(apply_button.first, company) if is_job_acceptable?(apply_button, company)
			sleep(LOAD_TIME)
		end


	end
end

JobBot.new

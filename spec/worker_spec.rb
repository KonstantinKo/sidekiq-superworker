require 'spec_helper'

# TODO: Clean up, write simpler tests!

describe Sidekiq::Superworker::Worker do
  include Sidekiq::Superworker::WorkerHelpers

  before :all do
    @queue = Sidekiq::Queue.new(dummy_worker_queue)
    clean_datastores
    create_dummy_workers

    # For testing complex blocks
    Sidekiq::Superworker::Worker.create(:ComplexSuperworker, :first_argument, :second_argument) do
      Worker1 :first_argument do       # 1
        Worker2 :second_argument       # 2
        Worker3 :second_argument do    # 3
          Worker4 :first_argument      # 4
          parallel do                  # 5
            Worker5 :first_argument    # 6
            Worker6 :first_argument do # 7
              Worker7 :first_argument  # 8
              Worker8 :first_argument  # 9
            end
          end
        end
        Worker9 :first_argument        # 10
      end
    end

    # For testing batch blocks
    Sidekiq::Superworker::Worker.create(:BatchSuperworker, :user_ids) do
      batch user_ids: :user_id do
        Worker1 :user_id
        Worker2 :user_id
      end
    end
    
    # For testing batch blocks with additional arguments
    Sidekiq::Superworker::Worker.create(:BatchArgsSuperworker, :title, :message, :user_ids) do
      batch title: :title, message: :message, user_ids: :user_id do
        Worker1 :title, :message, :user_id
      end
    end

    # For testing empty arguments
    Sidekiq::Superworker::Worker.create(:EmptyArgumentsSuperworker) do
      Worker1 do
        Worker2()
      end
    end

    # For testing nested superworkers
    Sidekiq::Superworker::Worker.create(:ChildSuperworker) do
      Worker2 do
        Worker3()
      end
    end
    Sidekiq::Superworker::Worker.create(:NestedSuperworker) do
      Worker1()
      ChildSuperworker()
    end
  end

  describe '.perform_async' do
    context 'batch superworker' do
      before :all do
        BatchSuperworker.perform_async([100, 101])
      end

      after :all do
        clean_datastores
      end

      it 'creates the correct Subjob records' do
        expected_record_hashes =
          {1=>
            {:subjob_id=>1,
             :parent_id=>nil,
             :children_ids=>[2, 5],
             :next_id=>nil,
             :subworker_class=>"batch",
             :superworker_class=>"BatchSuperworker",
             :arg_keys=>[{:user_ids=>:user_id}],
             :arg_values=>[{:user_ids=>:user_id}],
             :status=>"running",
             :descendants_are_complete=>false},
           2=>
            {:subjob_id=>2,
             :parent_id=>1,
             :children_ids=>nil,
             :next_id=>nil,
             :subworker_class=>"batch_child",
             :superworker_class=>"BatchSuperworker",
             :arg_keys=>[:user_id],
             :arg_values=>[100],
             :status=>"running",
             :descendants_are_complete=>false},
           3=>
            {:subjob_id=>3,
             :parent_id=>2,
             :children_ids=>nil,
             :next_id=>4,
             :subworker_class=>"Worker1",
             :superworker_class=>"BatchSuperworker",
             :arg_keys=>[:user_id],
             :arg_values=>[100],
             :status=>"queued",
             :descendants_are_complete=>false},
           4=>
            {:subjob_id=>4,
             :parent_id=>2,
             :children_ids=>nil,
             :next_id=>nil,
             :subworker_class=>"Worker2",
             :superworker_class=>"BatchSuperworker",
             :arg_keys=>[:user_id],
             :arg_values=>[100],
             :status=>"initialized",
             :descendants_are_complete=>false},
           5=>
            {:subjob_id=>5,
             :parent_id=>1,
             :children_ids=>nil,
             :next_id=>nil,
             :subworker_class=>"batch_child",
             :superworker_class=>"BatchSuperworker",
             :arg_keys=>[:user_id],
             :arg_values=>[101],
             :status=>"running",
             :descendants_are_complete=>false},
           6=>
            {:subjob_id=>6,
             :parent_id=>5,
             :children_ids=>nil,
             :next_id=>7,
             :subworker_class=>"Worker1",
             :superworker_class=>"BatchSuperworker",
             :arg_keys=>[:user_id],
             :arg_values=>[101],
             :status=>"queued",
             :descendants_are_complete=>false},
           7=>
            {:subjob_id=>7,
             :parent_id=>5,
             :children_ids=>nil,
             :next_id=>nil,
             :subworker_class=>"Worker2",
             :superworker_class=>"BatchSuperworker",
             :arg_keys=>[:user_id],
             :arg_values=>[101],
             :status=>"initialized",
             :descendants_are_complete=>false}}

        record_hashes = subjobs_to_indexed_hash(Sidekiq::Superworker::Subjob.all)
        record_hashes.should have(expected_record_hashes.length).items
        record_hashes.each do |subjob_id, record_hash|
          expected_record_hashes[subjob_id].should == record_hash
        end
      end
    end

    context 'batch superworker with args' do
      before :all do 
        BatchArgsSuperworker.perform_async('hello', 'world', [100, 101])
      end

      after :all do
        clean_datastores
      end

      it 'creates the correct Subjob records' do
        expected_record_hashes =
          {1=>
            {:subjob_id=>1,
             :parent_id=>nil,
             :children_ids=>[2, 4],
             :next_id=>nil,
             :subworker_class=>"batch",
             :superworker_class=>"BatchArgsSuperworker",
             :arg_keys=>[{:title=>:title, :message=>:message, :user_ids=>:user_id}],
             :arg_values=>[{:title=>:title, :message=>:message, :user_ids=>:user_id}],
             :status=>"running",
             :descendants_are_complete=>false},
           2=>
            {:subjob_id=>2,
             :parent_id=>1,
             :children_ids=>nil,
             :next_id=>nil,
             :subworker_class=>"batch_child",
             :superworker_class=>"BatchArgsSuperworker",
             :arg_keys=>[:title, :message, :user_id],
             :arg_values=>[100, 'hello', 'world'],
             :status=>"running",
             :descendants_are_complete=>false},
           3=>
            {:subjob_id=>3,
             :parent_id=>2,
             :children_ids=>nil,
             :next_id=>nil,
             :subworker_class=>"Worker1",
             :superworker_class=>"BatchArgsSuperworker",
             :arg_keys=>[:title, :message, :user_id],
             :arg_values=>[100, 'hello', 'world'],
             :status=>"queued",
             :descendants_are_complete=>false},
           4=>
            {:subjob_id=>4,
             :parent_id=>1,
             :children_ids=>nil,
             :next_id=>nil,
             :subworker_class=>"batch_child",
             :superworker_class=>"BatchArgsSuperworker",
             :arg_keys=>[:title, :message, :user_id],
             :arg_values=>[101, 'hello', 'world'],
             :status=>"running",
             :descendants_are_complete=>false},
           5=>
            {:subjob_id=>5,
             :parent_id=>4,
             :children_ids=>nil,
             :next_id=>nil,
             :subworker_class=>"Worker1",
             :superworker_class=>"BatchArgsSuperworker",
             :arg_keys=>[:title, :message, :user_id],
             :arg_values=>[101, 'hello', 'world'],
             :status=>"queued",
             :descendants_are_complete=>false}}

        record_hashes = subjobs_to_indexed_hash(Sidekiq::Superworker::Subjob.all)
        record_hashes.should have(expected_record_hashes.length).items
        record_hashes.each do |subjob_id, record_hash|
          expected_record_hashes[subjob_id].should == record_hash
        end
      end
    end

    context 'empty arguments superworker' do
      before :all do
        EmptyArgumentsSuperworker.perform_async
      end

      after :all do
        clean_datastores
      end

      it 'creates the correct Subjob records' do
        expected_record_hashes = {
         1=>
          {:subjob_id=>1,
           :parent_id=>nil,
           :children_ids=>[2],
           :next_id=>nil,
           :subworker_class=>"Worker1",
           :superworker_class=>"EmptyArgumentsSuperworker",
           :arg_keys=>[],
           :arg_values=>[],
           :status=>"queued",
           :descendants_are_complete=>false},
         2=>
          {:subjob_id=>2,
           :parent_id=>1,
           :children_ids=>nil,
           :next_id=>nil,
           :subworker_class=>"Worker2",
           :superworker_class=>"EmptyArgumentsSuperworker",
           :arg_keys=>[],
           :arg_values=>[],
           :status=>"initialized",
           :descendants_are_complete=>false}
        }

        record_hashes = subjobs_to_indexed_hash(Sidekiq::Superworker::Subjob.all)

        record_hashes.should have(expected_record_hashes.length).items
        record_hashes.each do |subjob_id, record_hash|
          expected_record_hashes[subjob_id].should == record_hash
        end
      end
    end

    context 'nested superworker' do
      before :all do
        NestedSuperworker.perform_async
      end

      after :all do
        clean_datastores
      end

      it 'creates the correct Subjob records' do
        expected_record_hashes = {
          1=>
            {:subjob_id=>1,
             :parent_id=>nil,
             :children_ids=>nil,
             :next_id=>2,
             :subworker_class=>"Worker1",
             :superworker_class=>"NestedSuperworker",
             :arg_keys=>[],
             :arg_values=>[],
             :status=>"queued",
             :descendants_are_complete=>false},
          2=>
            {:subjob_id=>2,
             :parent_id=>nil,
             :children_ids=>[3],
             :next_id=>nil,
             :subworker_class=>"ChildSuperworker",
             :superworker_class=>"NestedSuperworker",
             :arg_keys=>[],
             :arg_values=>[],
             :status=>"initialized",
             :descendants_are_complete=>false},
          3=>
            {:subjob_id=>3,
             :parent_id=>2,
             :children_ids=>[4],
             :next_id=>nil,
             :subworker_class=>"Worker2",
             :superworker_class=>"NestedSuperworker",
             :arg_keys=>[],
             :arg_values=>[],
             :status=>"initialized",
             :descendants_are_complete=>false},
          4=>
            {:subjob_id=>4,
             :parent_id=>3,
             :children_ids=>nil,
             :next_id=>nil,
             :subworker_class=>"Worker3",
             :superworker_class=>"NestedSuperworker",
             :arg_keys=>[],
             :arg_values=>[],
             :status=>"initialized",
             :descendants_are_complete=>false}
        }

        record_hashes = subjobs_to_indexed_hash(Sidekiq::Superworker::Subjob.all)

        record_hashes.should have(expected_record_hashes.length).items
        record_hashes.each do |subjob_id, record_hash|
          expected_record_hashes[subjob_id].should == record_hash
        end
      end
    end

    context 'complex superworker' do
      before :all do
        worker_perform_async(ComplexSuperworker)
      end
      
      after :all do
        clean_datastores
      end

      it 'creates the correct Subjob records' do
        expected_record_hashes = {
         1=>
          {:subjob_id=>1,
           :parent_id=>nil,
           :children_ids=>[2, 3, 10],
           :next_id=>nil,
           :subworker_class=>"Worker1",
           :superworker_class=>"ComplexSuperworker",
           :arg_keys=>[:first_argument],
           :arg_values=>[100],
           :status=>"queued",
           :descendants_are_complete=>false},
         2=>
          {:subjob_id=>2,
           :parent_id=>1,
           :children_ids=>nil,
           :next_id=>3,
           :subworker_class=>"Worker2",
           :superworker_class=>"ComplexSuperworker",
           :arg_keys=>[:second_argument],
           :arg_values=>[101],
           :status=>"initialized",
           :descendants_are_complete=>false},
         3=>
          {:subjob_id=>3,
           :parent_id=>1,
           :children_ids=>[4, 5],
           :next_id=>10,
           :subworker_class=>"Worker3",
           :superworker_class=>"ComplexSuperworker",
           :arg_keys=>[:second_argument],
           :arg_values=>[101],
           :status=>"initialized",
           :descendants_are_complete=>false},
         4=>
          {:subjob_id=>4,
           :parent_id=>3,
           :children_ids=>nil,
           :next_id=>5,
           :subworker_class=>"Worker4",
           :superworker_class=>"ComplexSuperworker",
           :arg_keys=>[:first_argument],
           :arg_values=>[100],
           :status=>"initialized",
           :descendants_are_complete=>false},
         5=>
          {:subjob_id=>5,
           :parent_id=>3,
           :children_ids=>[6, 7],
           :next_id=>nil,
           :subworker_class=>"parallel",
           :superworker_class=>"ComplexSuperworker",
           :arg_keys=>[],
           :arg_values=>[],
           :status=>"initialized",
           :descendants_are_complete=>false},
           6=>
          {:subjob_id=>6,
           :parent_id=>5,
           :children_ids=>nil,
           :next_id=>7,
           :subworker_class=>"Worker5",
           :superworker_class=>"ComplexSuperworker",
           :arg_keys=>[:first_argument],
           :arg_values=>[100],
           :status=>"initialized",
           :descendants_are_complete=>false},
         7=>
          {:subjob_id=>7,
           :parent_id=>5,
           :children_ids=>[8, 9],
           :next_id=>nil,
           :subworker_class=>"Worker6",
           :superworker_class=>"ComplexSuperworker",
           :arg_keys=>[:first_argument],
           :arg_values=>[100],
           :status=>"initialized",
           :descendants_are_complete=>false},
         8=>
          {:subjob_id=>8,
           :parent_id=>7,
           :children_ids=>nil,
           :next_id=>9,
           :subworker_class=>"Worker7",
           :superworker_class=>"ComplexSuperworker",
           :arg_keys=>[:first_argument],
           :arg_values=>[100],
           :status=>"initialized",
           :descendants_are_complete=>false},
         9=>
          {:subjob_id=>9,
           :parent_id=>7,
           :children_ids=>nil,
           :next_id=>nil,
           :subworker_class=>"Worker8",
           :superworker_class=>"ComplexSuperworker",
           :arg_keys=>[:first_argument],
           :arg_values=>[100],
           :status=>"initialized",
           :descendants_are_complete=>false},
         10=>
          {:subjob_id=>10,
           :parent_id=>1,
           :children_ids=>nil,
           :next_id=>nil,
           :subworker_class=>"Worker9",
           :superworker_class=>"ComplexSuperworker",
           :arg_keys=>[:first_argument],
           :arg_values=>[100],
           :status=>"initialized",
           :descendants_are_complete=>false}
        }

        record_hashes = subjobs_to_indexed_hash(Sidekiq::Superworker::Subjob.all)

        record_hashes.should have(expected_record_hashes.length).items
        record_hashes.each do |subjob_id, record_hash|
          expected_record_hashes[subjob_id].should == record_hash
        end
      end

      it 'creates enough Subjob records' do
        Sidekiq::Superworker::Subjob.count.should == 10
      end

      it 'queues root-level subjobs' do
        Sidekiq::Superworker::Subjob.where(subjob_id: 1).first.status.should == 'queued'
      end

      it 'creates a Sidekiq job for the first root-level subjob' do
        jobs = @queue.to_a
        first_job = jobs.first

        jobs.should have(1).items
        first_job.klass.should == 'Worker1'
        first_job.args.should == [100]
      end
    end
  end

  describe '.perform_async cascade' do
    after :each do
      clean_datastores
    end

    context 'batch superworker' do
      before :each do
        BatchSuperworker.perform_async([100, 101])
      end

      # subjob_id - subworker_class
      # 1 - batch
      # 2 - batch_child
      # 3 - Worker1
      # 4 - Worker2
      # 5 - batch_child
      # 6 - Worker1
      # 7 - Worker2

      it 'sets the correct initial statuses' do
        subjob_statuses_should_equal(
          [1,2,5] => 'running',
          [3,6] => 'queued',
          [4,7] => 'initialized'
        )
      end

      it 'sets the correct statuses after subjob #3 completes' do
        trigger_completion_of_sidekiq_job(3)
        subjob_statuses_should_equal(
          [1,2,5] => 'running',
          [3] => 'complete',
          [7] => 'initialized',
          [4,6] => 'queued'
        )
      end

      it 'sets the correct statuses after subjob #4 completes' do
        trigger_completion_of_sidekiq_job(3)
        trigger_completion_of_sidekiq_job(4)
        subjob_statuses_should_equal(
          [1,5] => 'running',
          [2,3,4] => 'complete',
          [7] => 'initialized',
          [6] => 'queued'
        )
      end

      it 'sets the correct statuses after subjob #6 completes' do
        trigger_completion_of_sidekiq_job(3)
        trigger_completion_of_sidekiq_job(4)
        trigger_completion_of_sidekiq_job(6)
        subjob_statuses_should_equal(
          [1,5] => 'running',
          [2,3,4,6] => 'complete',
          [7] => 'queued'
        )
      end

      it 'sets the correct statuses after subjob #7 completes' do
        trigger_completion_of_sidekiq_job(3)
        trigger_completion_of_sidekiq_job(4)
        trigger_completion_of_sidekiq_job(6)
        trigger_completion_of_sidekiq_job(7)
        subjob_statuses_should_equal(
          (1..7) => 'complete'
        )
      end
    end

    context 'complex superworker' do
      before :each do
        worker_perform_async(ComplexSuperworker)
      end

      it 'sets the correct statuses after subjob #1 completes' do
        trigger_completion_of_sidekiq_job(1)
        subjob_statuses_should_equal(
          1 => 'complete',
          2 => 'queued',
          (3..10) => 'initialized' 
        )
      end

      it 'sets the correct statuses after subjob #2 completes' do
        trigger_completion_of_sidekiq_job(1)
        trigger_completion_of_sidekiq_job(2)
        subjob_statuses_should_equal(
          1 => 'complete',
          2 => 'complete',
          3 => 'queued',
          (4..10) => 'initialized' 
        )
      end

      it 'sets the correct statuses after subjob #3 completes' do
        trigger_completion_of_sidekiq_job(1)
        trigger_completion_of_sidekiq_job(2)
        trigger_completion_of_sidekiq_job(3)
        subjob_statuses_should_equal(
          1 => 'complete',
          2 => 'complete',
          3 => 'complete',
          4 => 'queued',
          (5..10) => 'initialized' 
        )
      end

      it 'sets the correct statuses after subjob #4 completes' do
        trigger_completion_of_sidekiq_job(1)
        trigger_completion_of_sidekiq_job(2)
        trigger_completion_of_sidekiq_job(3)
        trigger_completion_of_sidekiq_job(4)
        subjob_statuses_should_equal(
          1 => 'complete',
          2 => 'complete',
          3 => 'complete',
          4 => 'complete',
          5 => 'running',
          6 => 'queued',
          7 => 'queued',
          (8..10) => 'initialized' 
        )
      end

      # Complete #7 before #6 to test parallel block
      it 'sets the correct statuses after subjob #7 completes' do
        trigger_completion_of_sidekiq_job(1)
        trigger_completion_of_sidekiq_job(2)
        trigger_completion_of_sidekiq_job(3)
        trigger_completion_of_sidekiq_job(4)
        trigger_completion_of_sidekiq_job(7)
        subjob_statuses_should_equal(
          1 => 'complete',
          2 => 'complete',
          3 => 'complete',
          4 => 'complete',
          5 => 'running',
          6 => 'queued',
          7 => 'complete',
          8 => 'queued',
          (9..10) => 'initialized' 
        )
      end

      it 'sets the correct statuses after subjobs #8 and #9 complete' do
        trigger_completion_of_sidekiq_job(1)
        trigger_completion_of_sidekiq_job(2)
        trigger_completion_of_sidekiq_job(3)
        trigger_completion_of_sidekiq_job(4)
        trigger_completion_of_sidekiq_job(7)
        trigger_completion_of_sidekiq_job(8)
        trigger_completion_of_sidekiq_job(9)
        subjob_statuses_should_equal(
          1 => 'complete',
          2 => 'complete',
          3 => 'complete',
          4 => 'complete',
          5 => 'running',
          6 => 'queued',
          7 => 'complete',
          8 => 'complete',
          9 => 'complete',
          10 => 'initialized' 
        )
      end

      it 'sets the correct statuses after subjob #6 completes' do
        trigger_completion_of_sidekiq_job(1)
        trigger_completion_of_sidekiq_job(2)
        trigger_completion_of_sidekiq_job(3)
        trigger_completion_of_sidekiq_job(4)
        trigger_completion_of_sidekiq_job(7)
        trigger_completion_of_sidekiq_job(8)
        trigger_completion_of_sidekiq_job(9)
        trigger_completion_of_sidekiq_job(6)
        subjob_statuses_should_equal(
          1 => 'complete',
          2 => 'complete',
          3 => 'complete',
          4 => 'complete',
          5 => 'complete',
          6 => 'complete',
          7 => 'complete',
          8 => 'complete',
          9 => 'complete',
          10 => 'queued' 
        )
      end

      it 'sets the correct statuses after subjob #10 completes' do
        trigger_completion_of_sidekiq_job(1)
        trigger_completion_of_sidekiq_job(2)
        trigger_completion_of_sidekiq_job(3)
        trigger_completion_of_sidekiq_job(4)
        trigger_completion_of_sidekiq_job(7)
        trigger_completion_of_sidekiq_job(8)
        trigger_completion_of_sidekiq_job(9)
        trigger_completion_of_sidekiq_job(6)
        trigger_completion_of_sidekiq_job(10)
        subjob_statuses_should_equal(
          (1..10) => 'complete'
        )
      end
    end
  end

  def worker_perform_async(worker)
    worker.perform_async(100, 101)
  end
end

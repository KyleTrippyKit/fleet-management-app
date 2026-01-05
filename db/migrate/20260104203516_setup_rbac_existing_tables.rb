class SetupRbacExistingTables < ActiveRecord::Migration[8.1]
  def up
    # === 1. Create Agencies if it doesn't exist ===
    unless table_exists?(:agencies)
      create_table :agencies do |t|
        t.string :code
        t.string :name
        t.string :agency_type
        t.timestamps
      end
    end

    # === 2. Create Roles if it doesn't exist ===
    unless table_exists?(:roles)
      create_table :roles do |t|
        t.string :name
        t.string :category
        t.boolean :is_system_admin, default: false
        t.boolean :requires_gps_approval, default: false
        t.timestamps
      end
    end

    # === 3. Create Permissions if it doesn't exist ===
    unless table_exists?(:permissions)
      create_table :permissions do |t|
        t.string :key
        t.string :category
        t.timestamps
      end
    end

    # === 4. Create Role Permissions if it doesn't exist ===
    unless table_exists?(:role_permissions)
      create_table :role_permissions do |t|
        t.references :role
        t.references :permission
        t.timestamps
      end
    end

    # === 5. Create User Roles if it doesn't exist ===
    unless table_exists?(:user_roles)
      create_table :user_roles do |t|
        t.references :user
        t.references :role
        t.references :agency
        t.timestamps
      end
    end

    # === 6. Add columns to Users if they don't exist ===
    unless column_exists?(:users, :agency_id)
      add_reference :users, :agency, foreign_key: true
    end
    
    unless column_exists?(:users, :employee_id)
      add_column :users, :employee_id, :string
    end
    
    unless column_exists?(:users, :division)
      add_column :users, :division, :string
    end
    
    unless column_exists?(:users, :is_active)
      add_column :users, :is_active, :boolean, default: true
    end
  end

  def down
    # We'll define rollback logic if needed
    # But for now, we'll leave it empty since we're fixing existing state
  end
end
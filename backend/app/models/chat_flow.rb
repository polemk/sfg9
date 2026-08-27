class ChatFlow < ApplicationRecord
  has_many :chat_sessions, dependent: :destroy
  has_many :flow_executions, dependent: :destroy
  belongs_to :credential, optional: true

  enum :kind, { chatbot: 0, ai_agent: 1 }

  validates :name, presence: true
  validates :definition, presence: true, if: :chatbot?
  validates :agent_config, presence: true, if: :ai_agent?
  validate :validate_agent_config_schema, if: :ai_agent?

  scope :by_keyword, ->(keyword) { 
    where("EXISTS (SELECT 1 FROM unnest(keywords) k WHERE :input ILIKE '%' || k || '%')", input: keyword.to_s.strip) 
  }
  scope :default_flow, -> { find_by(is_default: true) }
  scope :contextual, ->(user_type, route_path) {
    route_str = route_path.to_s
    
    where(
      "(? = ANY(mapped_routes) OR target_route_path = ?) AND target_user_type = ?", 
      route_str, route_str, user_type
    ).or(
      where("(? = ANY(mapped_routes) OR target_route_path = ?) AND target_user_type IS NULL", 
      route_str, route_str)
    ).or(
      where("mapped_routes = '{}' OR mapped_routes IS NULL").where(target_route_path: nil, target_user_type: user_type)
    ).order(Arel.sql(sanitize_sql_array([
      "CASE 
         WHEN (? = ANY(mapped_routes) OR target_route_path = ?) AND target_user_type = ? THEN 0 
         WHEN (? = ANY(mapped_routes) OR target_route_path = ?) THEN 1 
         WHEN target_user_type = ? THEN 2 
         ELSE 3 
       END",
      route_str, route_str, user_type,
      route_str, route_str,
      user_type
    ])))
  }

  before_save :ensure_single_default
  before_destroy :prevent_default_deletion

  def self.get_default
    find_by(is_default: true) || first
  end

  private

  def ensure_single_default
    return unless is_default && is_default_changed?
    ChatFlow.where.not(id: id).update_all(is_default: false)
  end

  def prevent_default_deletion
    if is_default
      errors.add(:base, "O fluxo padrão não pode ser removido.")
      throw(:abort)
    end
  end

  def validate_agent_config_schema
    return if agent_config.blank?

    required_keys = %w[model system_prompt]
    missing_keys = required_keys - agent_config.keys.map(&:to_s)

    if missing_keys.any?
      errors.add(:agent_config, "deve conter: #{missing_keys.join(', ')}")
    end
  end
end


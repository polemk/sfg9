flow = ChatFlow.find_by(name: 'Audio Visualizer Experiment')
if flow
  flow.update!(
    definition: {
      'nodes' => [
        {
          'id' => 'trigger-start',
          'type' => 'trigger',
          'position' => { 'x' => 100, 'y' => 100 },
          'data' => {
            'content' => 'Quer testar o nosso novo Visualizador de Áudio e mergulhar em uma experiência única?',
            'options' => [
              { 'id' => 'yes_option', 'label' => 'Sim, rock it', 'target' => 'play_music_node' },
              { 'id' => 'no_option', 'label' => 'Agora não', 'target' => 'end_no_music' }
            ],
            'isStart' => true
          }
        },
        {
          'id' => 'play_music_node',
          'type' => 'redirect',
          'position' => { 'x' => 400, 'y' => 100 },
          'data' => {
            'action' => 'play_audio',
            'songName' => 'Música'
          }
        },
        {
          'id' => 'end_no_music',
          'type' => 'message',
          'position' => { 'x' => 400, 'y' => 300 },
          'data' => {
            'content' => 'Tudo bem, você pode acessar depois através do menu!'
          }
        }
      ],
      'edges' => [
        { 'id' => 'e1', 'source' => 'trigger-start', 'target' => 'play_music_node', 'sourceHandle' => 'yes_option' },
        { 'id' => 'e2', 'source' => 'trigger-start', 'target' => 'end_no_music', 'sourceHandle' => 'no_option' }
      ]
    }
  )
  puts "Flow updated!"
end

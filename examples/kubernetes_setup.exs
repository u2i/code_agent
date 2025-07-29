#!/usr/bin/env elixir

# Kubernetes Configuration Setup Script
# 
# Usage:
#   curl -sSL https://raw.githubusercontent.com/u2i/code_agent/main/examples/kubernetes_setup.exs | elixir - [options]
#
# This script ensures your Kubernetes configuration files are properly set up
# according to best practices.

Mix.install([
  {:code_agent, github: "u2i/code_agent"}
])

defmodule KubernetesSetup do
  alias CodeAgent.ConfigAgent
  
  @config_spec %{
    instructions: """
    Set up a standard Kubernetes application deployment structure with:
    - Namespace for isolation
    - Deployment with proper resource limits
    - Service for internal networking
    - ConfigMap for configuration
    - Horizontal Pod Autoscaler for scaling
    """,
    
    templates: %{
      "namespace" => """
      apiVersion: v1
      kind: Namespace
      metadata:
        name: {{APP_NAME}}
        labels:
          app: {{APP_NAME}}
          environment: {{ENVIRONMENT}}
      """,
      
      "deployment" => """
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: {{APP_NAME}}
        namespace: {{APP_NAME}}
        labels:
          app: {{APP_NAME}}
      spec:
        replicas: {{REPLICAS}}
        selector:
          matchLabels:
            app: {{APP_NAME}}
        template:
          metadata:
            labels:
              app: {{APP_NAME}}
          spec:
            containers:
            - name: {{APP_NAME}}
              image: {{IMAGE}}
              ports:
              - containerPort: {{PORT}}
              resources:
                requests:
                  memory: "{{MEMORY_REQUEST}}"
                  cpu: "{{CPU_REQUEST}}"
                limits:
                  memory: "{{MEMORY_LIMIT}}"
                  cpu: "{{CPU_LIMIT}}"
              envFrom:
              - configMapRef:
                  name: {{APP_NAME}}-config
      """,
      
      "service" => """
      apiVersion: v1
      kind: Service
      metadata:
        name: {{APP_NAME}}
        namespace: {{APP_NAME}}
      spec:
        selector:
          app: {{APP_NAME}}
        ports:
        - protocol: TCP
          port: {{SERVICE_PORT}}
          targetPort: {{PORT}}
        type: ClusterIP
      """,
      
      "configmap" => """
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: {{APP_NAME}}-config
        namespace: {{APP_NAME}}
      data:
        # Add your configuration here
        LOG_LEVEL: "info"
        DATABASE_POOL_SIZE: "10"
      """,
      
      "hpa" => """
      apiVersion: autoscaling/v2
      kind: HorizontalPodAutoscaler
      metadata:
        name: {{APP_NAME}}
        namespace: {{APP_NAME}}
      spec:
        scaleTargetRef:
          apiVersion: apps/v1
          kind: Deployment
          name: {{APP_NAME}}
        minReplicas: {{MIN_REPLICAS}}
        maxReplicas: {{MAX_REPLICAS}}
        metrics:
        - type: Resource
          resource:
            name: cpu
            target:
              type: Utilization
              averageUtilization: 70
        - type: Resource
          resource:
            name: memory
            target:
              type: Utilization
              averageUtilization: 80
      """
    },
    
    files: [
      %{
        path: "k8s/namespace.yaml",
        description: "Kubernetes namespace manifest for application isolation",
        template: "namespace",
        format: "yaml"
      },
      %{
        path: "k8s/deployment.yaml",
        description: "Kubernetes deployment manifest with proper resource limits and health checks",
        template: "deployment",
        format: "yaml"
      },
      %{
        path: "k8s/service.yaml",
        description: "Kubernetes service manifest for internal cluster networking",
        template: "service",
        format: "yaml"
      },
      %{
        path: "k8s/configmap.yaml",
        description: "ConfigMap for application configuration",
        template: "configmap",
        format: "yaml"
      },
      %{
        path: "k8s/hpa.yaml",
        description: "Horizontal Pod Autoscaler for automatic scaling based on CPU and memory",
        template: "hpa",
        format: "yaml"
      },
      %{
        path: "k8s/kustomization.yaml",
        description: "Kustomization file to manage all resources together",
        template: """
        apiVersion: kustomize.config.k8s.io/v1beta1
        kind: Kustomization
        
        namespace: {{APP_NAME}}
        
        resources:
          - namespace.yaml
          - configmap.yaml
          - deployment.yaml
          - service.yaml
          - hpa.yaml
        
        commonLabels:
          app: {{APP_NAME}}
          managed-by: kustomize
        """,
        format: "yaml"
      }
    ]
  }
  
  def run(args \\ []) do
    # Parse arguments
    {opts, _, _} = OptionParser.parse(args,
      switches: [
        help: :boolean,
        check: :boolean,
        dir: :string,
        app_name: :string,
        environment: :string,
        image: :string,
        port: :integer,
        service_port: :integer,
        replicas: :integer,
        min_replicas: :integer,
        max_replicas: :integer,
        cpu_request: :string,
        cpu_limit: :string,
        memory_request: :string,
        memory_limit: :string
      ],
      aliases: [h: :help, c: :check, d: :dir]
    )
    
    if opts[:help] do
      print_help()
      System.halt(0)
    end
    
    # Set defaults
    dir = opts[:dir] || "."
    config = apply_defaults(opts)
    
    # Replace template variables
    spec = replace_variables(@config_spec, config)
    
    IO.puts("🚀 Kubernetes Configuration Manager")
    IO.puts("Directory: #{dir}")
    IO.puts("")
    
    # Ensure ANTHROPIC_API_KEY is set
    unless System.get_env("ANTHROPIC_API_KEY") do
      IO.puts("❌ Error: ANTHROPIC_API_KEY environment variable is required")
      IO.puts("  export ANTHROPIC_API_KEY='your-api-key'")
      System.halt(1)
    end
    
    if opts[:check] do
      # Check compliance only
      IO.puts("📋 Checking configuration compliance...")
      
      case ConfigAgent.check_compliance(dir, spec) do
        %{compliant: true} ->
          IO.puts("✅ All files are compliant!")
          System.halt(0)
          
        %{compliant: false, files: files} ->
          IO.puts("❌ Some files are not compliant:\n")
          
          Enum.each(files, fn file ->
            unless file.compliant do
              IO.puts("  • #{file.path}: #{file.reason}")
              if file[:missing] && length(file.missing) > 0 do
                IO.puts("    Missing: #{Enum.join(file.missing, ", ")}")
              end
              if file[:incorrect] && length(file.incorrect) > 0 do
                IO.puts("    Incorrect: #{Enum.join(file.incorrect, ", ")}")
              end
            end
          end)
          
          System.halt(1)
      end
    else
      # Apply configuration
      IO.puts("🔧 Ensuring Kubernetes configuration...")
      
      case ConfigAgent.ensure_configuration(dir, spec) do
        {:ok, results} ->
          IO.puts("\n✅ Configuration complete!\n")
          
          Enum.each(results, fn {:ok, result} ->
            if length(result.operations) > 0 do
              IO.puts("  • #{result.path}: #{result.summary}")
            else
              IO.puts("  • #{result.path}: Already compliant")
            end
          end)
          
          IO.puts("\n📝 Next steps:")
          IO.puts("  1. Review the generated files in #{Path.join(dir, "k8s/")}")
          IO.puts("  2. Update placeholder values ({{...}}) with your actual values")
          IO.puts("  3. Apply to your cluster: kubectl apply -k #{Path.join(dir, "k8s/")}")
          
        {:error, {:failed_files, errors}} ->
          IO.puts("\n❌ Some files failed:")
          
          Enum.each(errors, fn {:error, {path, reason}} ->
            IO.puts("  • #{path}: #{inspect(reason)}")
          end)
          
          System.halt(1)
      end
    end
  end
  
  defp apply_defaults(opts) do
    %{
      app_name: opts[:app_name] || "my-app",
      environment: opts[:environment] || "production",
      image: opts[:image] || "my-app:latest",
      port: opts[:port] || 8080,
      service_port: opts[:service_port] || 80,
      replicas: opts[:replicas] || 2,
      min_replicas: opts[:min_replicas] || 2,
      max_replicas: opts[:max_replicas] || 10,
      cpu_request: opts[:cpu_request] || "100m",
      cpu_limit: opts[:cpu_limit] || "500m",
      memory_request: opts[:memory_request] || "128Mi",
      memory_limit: opts[:memory_limit] || "512Mi"
    }
  end
  
  defp replace_variables(spec, config) do
    # Replace variables in templates
    updated_templates = spec.templates
    |> Enum.map(fn {name, template} ->
      updated = Enum.reduce(config, template, fn {key, value}, acc ->
        String.replace(acc, "{{#{key |> to_string() |> String.upcase()}}}", to_string(value))
      end)
      {name, updated}
    end)
    |> Enum.into(%{})
    
    # Replace variables in inline templates
    updated_files = Enum.map(spec.files, fn file ->
      if file[:template] && !Map.has_key?(spec.templates, file.template) do
        # Inline template
        updated_template = Enum.reduce(config, file.template, fn {key, value}, acc ->
          String.replace(acc, "{{#{key |> to_string() |> String.upcase()}}}", to_string(value))
        end)
        Map.put(file, :template, updated_template)
      else
        file
      end
    end)
    
    %{spec | templates: updated_templates, files: updated_files}
  end
  
  defp print_help do
    IO.puts("""
    Kubernetes Configuration Setup
    
    Usage:
      ./kubernetes_setup.exs [options]
    
    Options:
      -h, --help              Show this help
      -c, --check             Check compliance without making changes
      -d, --dir PATH          Target directory (default: current directory)
      
      --app-name NAME         Application name (default: my-app)
      --environment ENV       Environment (default: production)
      --image IMAGE          Docker image (default: my-app:latest)
      --port PORT            Container port (default: 8080)
      --service-port PORT    Service port (default: 80)
      
      --replicas N           Initial replicas (default: 2)
      --min-replicas N       Minimum replicas for HPA (default: 2)
      --max-replicas N       Maximum replicas for HPA (default: 10)
      
      --cpu-request VALUE    CPU request (default: 100m)
      --cpu-limit VALUE      CPU limit (default: 500m)
      --memory-request VALUE Memory request (default: 128Mi)
      --memory-limit VALUE   Memory limit (default: 512Mi)
    
    Environment Variables:
      ANTHROPIC_API_KEY      Required for AI-powered configuration
    
    Examples:
      # Basic setup with defaults
      ./kubernetes_setup.exs
      
      # Custom application setup
      ./kubernetes_setup.exs --app-name api-service --port 3000
      
      # Check compliance only
      ./kubernetes_setup.exs --check
      
      # Run via curl
      curl -sSL https://example.com/k8s-setup.exs | elixir - --app-name myapp
    """)
  end
end

# Run the script
KubernetesSetup.run(System.argv())
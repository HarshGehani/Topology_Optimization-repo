% FEM SOLVER
function z=TopOpt()
volfrac = 0.6;
p=3;
R=3;
% length = 1; breadth = 0.25;height = 0.25;             % Dimensions of the beam
nX = 10; nY = 2; nZ = 1;               % No. of cells in x,y-directions

% dx = length/nX; dy = breadth/nY;      % Dimensions of each element
% dz = height/nZ;
dx = 1; dy = 1; dz = 1; 
length = nX*dx; breadth = nY*dy;
height = nZ*dz;

if nZ == 1
    nodesPerElement = 4;	% Considering linear quadrilateral elements
    dofPerNode = 2;
    nNodes = (nX + 1)*(nY + 1);
else
    nodesPerElement = 8;
    dofPerNode = 3;
    nNodes = (nX + 1)*(nY + 1)*(nZ + 1);
end

nElem = nX*nY*nZ;                          % Total number of elements

E_0 = 1;
E_min = 1e-7;

%x0 = volfrac*ones(nY*nX*nZ,1);
%x0 = ones(nY*nX*nZ,1);
x0 = volfrac*ones(nY,nX,nZ);

%x0 = ones(nY*nX*nZ);

maxloop = 200;    % Maximum number of iterations
tolx = 0.00001;   

f=@(x) FEMSolver(x);
disp(f(x0));


% OPTIMIZATION
% %A = -x0;
% %B = volfrac;
A= [];
B= [];
Aeq = [];
Beq = [];
LB = zeros(size(x0));
UB = ones(size(x0));

%options = optimoptions(@fmincon,'Algorithm','interior-point','GradObj','on','GradConstr','on','TolX',tolx, 'MaxIter',maxloop,'Display','iter');

options = optimoptions(@fmincon,'Algorithm','interior-point','GradObj','on','GradConstr','on','MaxIter',maxloop,'Display','iter');

z = fmincon(@FEMSolver, x0, A, B, Aeq, Beq, LB, UB, @nonlcon,options);
%disp (z);


% FEM Solver (Objective function)
function [f,gradf]=FEMSolver(x)
    % Elemental densities
    %x = sym('x',[nX nY]);
    %x = ones(nY,nX);
    %E_i = E_0*ones(nY*nX*nZ,1) + (x.^p)*(E_0 - E_min);
    xphys = density_filter(x,R);
    %E_i = E_0*ones(nY,nX,nZ) + (x.^p)*(E_0 - E_min);
    E_i = E_0*ones(nY,nX,nZ) + (xphys.^p)*(E_0 - E_min);

    % Elemental stiffness matrix
    k = zeros(dofPerNode*nodesPerElement,dofPerNode*nodesPerElement,nElem);

    % Global Load vector
    F = zeros(dofPerNode*nNodes,1);
    if nZ == 1        
        F(2*(nX + 1)) = -1;                            % 2D (load in the -Y direction)        
        % Setting up the boundary conditions (Indices of the rows and columns to be deleted from K and F)
        boundaryNodeIndices = zeros(1,2*(nY + 1));        % 2D
    else
        for i = 1:nY + 1
            F(3*i*(nX + 1)) = -1;                      % 3D (load in the -Z direction, along the bottom edge)
        end
        % Setting up the boundary conditions (Indices of the rows and columns to be deleted from K and F)
        boundaryNodeIndices = zeros(1,2*(nY + 1)*(nZ + 1)); % 3D
    end
    
%     F_reshaped = reshape(F',[],3);
%     forceIndices = find(F ~= 0);
    
if nZ ~= 1
%     Forming the connectivity matrix (3D)
    Conn = zeros(nElem,nodesPerElement);
    i = 1; boundaryCount = 1; z_idx = 0;                % z_idx is basically the z-coordinate
    nNodes_xy = (nX + 1)*(nY + 1);
    for e = 1:nElem
        lowerFace = [i + z_idx*nNodes_xy,i + 1 + z_idx*nNodes_xy,i + nX + 2 + z_idx*nNodes_xy,i + nX + 1 + z_idx*nNodes_xy];
        upperFace = [i + (z_idx +  1)*nNodes_xy,i + 1 + (z_idx +  1)*nNodes_xy, i + nX + 2 + (z_idx +  1)*nNodes_xy, i + nX + 1 + (z_idx +  1)*nNodes_xy];
        Conn(e,:) = [lowerFace,upperFace];

        % Checking for boundary nodes
        if mod(e,nX) == 1
            boundaryNodeIndices(boundaryCount:boundaryCount + 2) = [3*lowerFace(1) - 2,3*lowerFace(1) - 1,3*lowerFace(1)];
            boundaryNodeIndices(boundaryCount + 3:boundaryCount + 5) = [3*lowerFace(4) - 2,3*lowerFace(4) - 1,3*lowerFace(4)];
            boundaryNodeIndices(boundaryCount + 6:boundaryCount + 8) = [3*upperFace(1) - 2,3*upperFace(1) - 1,3*upperFace(1)];
            boundaryNodeIndices(boundaryCount + 9:boundaryCount + 11) = [3*upperFace(4) - 2,3*upperFace(4) - 1,3*upperFace(4)];
            boundaryCount = boundaryCount + 12;
        end

        i = i + 1;
        if i == nNodes_xy
           z_idx = z_idx + 1;
           i = 1;
        end
        if mod(i,nX + 1) == 0
            i = i + 1;
        end
    end
    boundaryNodeIndices = unique(boundaryNodeIndices);
else
    % Forming the connectivity matrix (2D)
    Conn = zeros(nElem,nodesPerElement);
    i = 1; boundaryCount = 1;
    for e = 1:nElem
        % Checking for boundary nodes
        if mod(e,nX) == 1
            boundaryNodeIndices(boundaryCount:boundaryCount + 1) = [2*i - 1,2*i];
            boundaryNodeIndices(boundaryCount + 2:boundaryCount + 3) = [2*(i + nX + 1) - 1,2*(i + nX + 1)];
            boundaryCount = boundaryCount + 4;
        end
        Conn(e,:) = [i,i + 1,i + nX + 2,i + nX + 1];
        i = i + 1;
        if i == nX + 1
            i = i + 1;
        end
    end
    boundaryNodeIndices = unique(boundaryNodeIndices);
end    
    % Calculating the elemental stiffness matrices
    i = 1; j = 1;k_z = 1;
    if nZ == 1
        k_element = Elem_stiffness(x(i,j), dx, dy);                 % Elemental stiffness matrix
    else
        k_element = Elem_stiffness_3D(dx, dy,dz);                   % Elemental stiffness matrix
    end
%     k_element = elem_stiffness_check();                           % Elemental stiffness matrix from SOTA formula
    for e = 1:nElem
        k(:,:,e) = k(:,:,e) + k_element;
        j = j + 1;
        if j > nX
            j = 1;
            i = i + 1;
        end
        if i > nY
               k_z = k_z + 1;
               i = 1;
        end
    end

    % Assembling the global stiffness matrix
    [K,K0] = globalAssembly(E_i,Conn,k,dofPerNode,nX,nY,nZ);
    K = 0.5*(K + K');
%   temp_s = k(:,:,1);
    indices = 1:dofPerNode*nNodes;                  % Indices of all the nodes
    indices(boundaryNodeIndices) = [];

    % Removing the rows + columns that correspond to nDOFs = 0 (Boundary nodes)
    K(boundaryNodeIndices,:) = [];                      % Rows
    K(:,boundaryNodeIndices) = [];                      % Columns

    F_calc = F;
    F_calc(boundaryNodeIndices) = [];                   % Rows 
   
    %F(:,boundaryNodeIndices) = [];                     % Columns
    
    
    u = K\F_calc;                                            % Nodal Displacement vector
    % u_x = reshape(u(1:2:end),2,6);
    % u_y = reshape(u(2:2:end),2,6);

    % Re-inserting the boundary nodes into the displacement matrix
    U = zeros(dofPerNode*nNodes,1);
    U(indices) = u;
    U(boundaryNodeIndices) = 0;

    %f=F'*u;
    f = F'*U;
    %viewMatrix(u);
    
    %gradf = zeros((nY*nX*nZ),1);
    gradf = zeros(nY,nX,nZ);
    
    for t=1:nElem
        [W,x_new]=density_grad(x(t),xphys,R);
        for t1= 1:size(W)
            %gradf(t) = -U'*(p*(xphys(t)^(p-1))*(E_0-E_min)*K0)*U;
            gradf(t) = gradf(t) + ((-U'*(p*(x_new(t1)^(p-1))*(E_0-E_min)*K0)*U)*(W(t1)/sum(W)));
        end
    end
    %gradf
end

% Non-linear constraints (volume fraction)
function [c, ceq, gradc, gradceq] = nonlcon(x)
        
        %c = sum((x'*v)) - volfrac*nX*nX;
        %c = sum(sum((dy*dx*dz)*(x))) - volfrac*length*breadth*height;
        c = sum(x(:)) - volfrac*nElem;
        gradc = ones(nElem,1);
        ceq = [];
        gradceq = [];
end

    function xphys = density_filter(x,R)
        xphys = zeros(size(x));        
        for t=1:nElem
            [i0,j0,k0] = ind2sub([nY,nX,nZ],t);
            W = 0;
            x_new = 0;
            for i=1:nY
                for j=1:nX
                    for k=1:nZ
                        dist = norm([i,j,k]-[i0,j0,k0]);
                        if dist <=R
                            W0 = R - dist;
                            x_new= x_new + W0*x(i,j,k);
                            W= W + W0;
                        end
                    end
                end
            end
            xphys(t) = (x_new/W);
        end
    end

    function [W,x_new]=density_grad(t0,xphys,R)               
            [i0,j0,k0] = ind2sub([nY,nX,nZ],t0);          
            W = [];
            x_new = [];
            for i=1:nY
                for j=1:nX
                    for k=1:nZ
                        dist = norm([i,j,k]-[i0,j0,k0]);
                        if dist <=R
                            W =[W, R - dist];                            
                            x_new = [x_new, xphys(i,j,k)];
                        end
                    end
                end
            end            
    end       
end

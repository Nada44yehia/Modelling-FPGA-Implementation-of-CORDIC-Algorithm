clc; clear;

%% ---------------- Parameters ----------------
FRACT_BITS_ANGLE = 20;   % Q12.20 format (angles)
FRACT_BITS_OUT   = 14;   % Q2.14 format (outputs)
N_ITER = 15;             % iterations

% CORDIC gain constant
K = prod(1 ./ sqrt(1 + 2.^(-2*(0:N_ITER-1))));

% Constants in Q12.20
PI_Q20     = int32(round(pi     * 2^FRACT_BITS_ANGLE));
PI_2_Q20   = int32(round(pi/2   * 2^FRACT_BITS_ANGLE));
TWO_PI_Q20 = int32(round(2*pi   * 2^FRACT_BITS_ANGLE));

%% ---------------- Arctan Table (Q12.20) ----------------
atan_table = int32(round(atan(2.^-(0:N_ITER-1)) * 2^FRACT_BITS_ANGLE));
% ============================== % Save atan lookup table % ============================== 
filename = 'atan_table_verilog.txt'; fid = fopen(filename, 'w'); 
for i = 1:N_ITER 
    fprintf(fid, '%08X\n', atan_table(i)); % 8 hex digits 
end
fclose(fid); 
fprintf('atan_table written to %s successfully!\n', filename);

rng(0);
%% ---------------- Test Angles (deg) ----------------
angles_deg = [ ...
    0, 90, 180, 270, 360, ...         % unit circle checkpoints
    450, -90, -360, 720, ...    % wrap-around
    randi([-360 720], 1, 20) ,...    % 20 random test angles
   55.5 ,698.889 ,432.567 ,...... %decimal angles 
   -117341.7564 ,117341.7564 %Angles at the maximum and minimum values of the fixed point format
];

% Convert degrees -> radians -> Q12.20
angles_q20 = int32(round((angles_deg * pi / 180) * 2^FRACT_BITS_ANGLE));

%% ---------------- Open File ----------------
fid = fopen('cordic_vectors.txt', 'w');

fprintf("Angle(deg)|Angle(Q12.20)|cosCORDIC| sinCORDIC | cosRef    | sinRef   |cos(Q2.14)|sin(Q2.14) \n");
fprintf("-------------------------------------------------------------------------------\n");

for k = 1:length(angles_q20)
    z = angles_q20(k);

    % ---- Wrap into [0, 2π)
    while z >= TWO_PI_Q20, z = z - TWO_PI_Q20; end
    while z <  0,          z = z + TWO_PI_Q20; end

    % ---- Quadrant handling
    flip_x = 0; flip_y = 0;
    if z <= PI_2_Q20
        % Quadrant I
    elseif z <= PI_Q20
        z = PI_Q20 - z; flip_x = 1;
    elseif z <= (PI_Q20 + PI_2_Q20)
        z = z - PI_Q20; flip_x = 1; flip_y = 1;
    else
        z = TWO_PI_Q20 - z; flip_y = 1;
    end

    % ---- Initialize vector (Q2.14, 16-bit)
    x = int16(round(K * 2^FRACT_BITS_OUT));
    y = int16(0);

    % ---- CORDIC iterations
    for i = 0:N_ITER-1
        if z >= 0
            x_new = int16(x - bitshift(y, -i));
            y_new = int16(y + bitshift(x, -i));
            z = z - atan_table(i+1);
        else
            x_new = int16(x + bitshift(y, -i));
            y_new = int16(y - bitshift(x, -i));
            z = z + atan_table(i+1);
        end
        x = x_new;
        y = y_new;
    end

    % ---- Apply flips
    if flip_x, x = -x; end
    if flip_y, y = -y; end

    % ---- Convert back to floating-point for reference
    angle_rad = double(angles_deg(k)) * pi/180;
    cos_val = double(x) / 2^FRACT_BITS_OUT;
    sin_val = double(y) / 2^FRACT_BITS_OUT;

  fprintf("%10d |%10d| %+1.6f | %+1.6f | %+1.6f | %+1.6f | %6d | %6d\n",angles_deg(k),angles_q20(k), cos_val, sin_val, cos(angle_rad), sin(angle_rad), x, y);

    % ---- Save to file (hex)
    fprintf(fid, "%d %d %d\n", ...
       angles_q20(k),x, y);
end

fclose(fid);
disp(' vectors saved to cordic_vectors.txt');
